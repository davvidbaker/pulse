defmodule Pulse.Accounts do
  @moduledoc """
  The Accounts context. Owns User and UserToken.
  Handles registration, authentication, password reset, and email confirmation.
  """

  import Ecto.Query
  alias Pulse.Repo
  alias Pulse.Accounts.{User, UserToken, UserNotifier}

  ## User queries

  @spec get_user!(binary()) :: User.t()
  def get_user!(id), do: Repo.get!(User, id)

  @spec get_user_by_email(String.t()) :: User.t() | nil
  def get_user_by_email(email) when is_binary(email) and byte_size(email) <= 320 do
    Repo.get_by(User, email: User.normalize_email(email))
  end

  def get_user_by_email(_), do: nil

  @spec get_user_by_email_and_password(String.t(), String.t()) :: User.t() | nil
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and byte_size(email) <= 320 and is_binary(password) do
    user = Repo.get_by(User, email: User.normalize_email(email))
    if User.valid_password?(user, password), do: user
  end

  def get_user_by_email_and_password(_, _) do
    User.valid_password?(nil, nil)
    nil
  end

  ## Registration

  @spec register_user(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @spec change_user_registration(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false, validate_email: false)
  end

  ## Settings

  @spec change_user_email(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs, validate_email: false)
  end

  @spec apply_user_email(User.t(), String.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def apply_user_email(user, password, attrs) do
    user = get_user!(user.id)

    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @spec update_user_email(User.t(), String.t()) :: :ok | :error
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(user_email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset =
      user
      |> User.email_changeset(%{email: email})
      |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, [context]))
  end

  @spec deliver_user_update_email_instructions(User.t(), String.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()}
  def deliver_user_update_email_instructions(
        %User{} = user,
        current_email,
        update_email_url_fun
      )
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @spec change_user_password(User.t(), map()) :: Ecto.Changeset.t()
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @spec update_user_password(User.t(), String.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_password(user, password, attrs) do
    Repo.transaction(fn ->
      current_user = Repo.one!(from(u in User, where: u.id == ^user.id, lock: "FOR UPDATE"))

      current_user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)
      |> persist_password_change()
    end)
    |> finish_password_change()
  end

  @spec change_user_settings(User.t()) :: Ecto.Changeset.t()
  def change_user_settings(%User{} = user, attrs \\ %{}) do
    User.settings_changeset(user, attrs)
  end

  @spec update_user_settings(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_user_settings(user, attrs) do
    Pulse.Footprint.transaction(user.id, fn ->
      case user |> User.settings_changeset(attrs) |> Repo.update() do
        {:ok, saved} ->
          if saved.timezone != user.timezone, do: Pulse.Footprint.invalidate(user.id)
          saved

        {:error, cs} ->
          Repo.rollback(cs)
      end
    end)
  end

  ## Session

  @spec generate_user_session_token(User.t()) :: binary()
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @spec get_user_by_session_token(binary()) :: User.t() | nil
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @spec delete_user_session_token(binary()) :: :ok
  def delete_user_session_token(token) do
    Repo.delete_all(UserToken.by_token_and_context_query(token, "session"))
    :ok
  end

  ## Confirmation

  @spec deliver_user_confirmation_instructions(User.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()}
  def deliver_user_confirmation_instructions(%User{} = user, confirmation_url_fun)
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)
      UserNotifier.deliver_confirmation_instructions(user, confirmation_url_fun.(encoded_token))
    end
  end

  @spec confirm_user(String.t()) :: {:ok, User.t()} | :error
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, ["confirm"]))
  end

  ## Reset password

  @spec deliver_user_reset_password_instructions(User.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()}
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @spec get_user_by_reset_password_token(String.t()) :: User.t() | nil
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @spec reset_user_password(String.t(), map()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t() | :invalid_token}
  def reset_user_password(token, attrs) when is_binary(token) and is_map(attrs) do
    Repo.transaction(fn ->
      with {:ok, query} <- UserToken.verify_email_token_query(token, "reset_password"),
           %User{} = user <- Repo.one(query) do
        # Serialize resets for this user, then recheck token validity under the lock.
        # This also rejects forms mounted before a token was consumed or expired.
        Repo.one!(from(u in User, where: u.id == ^user.id, lock: "FOR UPDATE"))

        case Repo.one(query) do
          %User{} = current_user ->
            persist_password_change(User.password_changeset(current_user, attrs))

          nil ->
            Repo.rollback(:invalid_token)
        end
      else
        _ -> Repo.rollback(:invalid_token)
      end
    end)
    |> finish_password_change()
  end

  def reset_user_password(_, _), do: {:error, :invalid_token}

  defp persist_password_change(changeset) do
    case Repo.update(changeset) do
      {:ok, user} ->
        sessions =
          Repo.all(
            from(t in UserToken,
              where: t.user_id == ^user.id and t.context == "session",
              select: t.token
            )
          )

        Repo.delete_all(UserToken.by_user_and_contexts_query(user, :all))
        {user, sessions}

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end

  defp finish_password_change({:ok, {user, sessions}}) do
    for token <- sessions do
      PulseWeb.Endpoint.broadcast("users_sessions:#{Base.url_encode64(token)}", "disconnect", %{})
    end

    {:ok, user}
  end

  defp finish_password_change({:error, reason}), do: {:error, reason}
end
