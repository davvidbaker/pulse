# CLAUDE.md — Pulse

This file provides guidance for AI assistants (Claude, etc.) working in this repository.

## Project Overview

**Pulse** is an Elixir application in early scaffolding stage. As of initial commit, no source code exists yet — only the project skeleton (LICENSE, README, .gitignore).

## Tech Stack

- **Language**: Elixir / Erlang (inferred from `.gitignore` patterns)
- **Expected tooling**: Mix (build tool), ExUnit (testing), possibly Phoenix (web framework)

## Repository Structure

```
pulse/
├── CLAUDE.md          # This file
├── LICENSE            # MIT License
├── README.md          # Minimal project description
└── .gitignore         # Elixir/Erlang artifact exclusions
```

### Expected structure once scaffolded

```
pulse/
├── config/            # App configuration (dev.exs, prod.exs, runtime.exs, etc.)
│   └── *.secret.exs   # Secret configs — gitignored, never commit
├── lib/               # Application source code
│   └── pulse/         # Core modules
├── test/              # ExUnit tests
├── mix.exs            # Project definition and dependencies
└── mix.lock           # Locked dependency versions
```

## Development Workflow

### Setup

```bash
mix deps.get          # Install dependencies
mix compile           # Compile the project
```

### Running tests

```bash
mix test              # Run all tests
mix test path/to/file_test.exs  # Run a specific test file
```

### Common Mix tasks

```bash
mix format            # Format code (enforce with mix format --check-formatted in CI)
mix credo             # Static analysis (if Credo is added as a dep)
mix dialyzer          # Type checking (if Dialyxir is added as a dep)
```

## Conventions

- **Formatting**: Always run `mix format` before committing. Elixir code must follow the standard formatter.
- **Secrets**: Never commit files matching `/config/*.secret.exs` — these are gitignored.
- **Build artifacts**: `_build/`, `deps/`, `cover/`, `doc/`, `.fetch/` are all gitignored — do not commit them.
- **Module naming**: Follow Elixir conventions — modules under `PascalCase`, functions in `snake_case`.
- **Tests**: Test files live in `test/` and are named `*_test.exs`. Use `ExUnit` assertions.

## Git Branches

- `main` — stable branch
- Feature branches follow the pattern `claude/<description>-<ID>` for AI-assisted work

## Notes for AI Assistants

- This project is in early initialization. No `mix.exs` exists yet — do not assume any specific dependencies or Phoenix version without checking.
- Before suggesting code, confirm whether `mix.exs` and `lib/` have been created.
- When creating Elixir modules, follow the `Pulse.*` namespace (e.g., `Pulse.Accounts`, `Pulse.Web`).
- Do not add documentation files (other than updating this CLAUDE.md) unless explicitly requested.
- Update this file whenever significant structural decisions are made (new dependencies, architecture choices, testing conventions, etc.).
