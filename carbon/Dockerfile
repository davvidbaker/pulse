FROM python:3.12-slim-bookworm

RUN apt-get update -y && apt-get install -y --no-install-recommends \
      nginx apache2-utils \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY pyproject.toml ./
COPY src ./src
RUN pip install --no-cache-dir .

COPY dagster.yaml workspace.yaml start.sh nginx.conf ./
RUN chmod +x start.sh \
    && mkdir -p /opt/dagster/home \
    && cp dagster.yaml workspace.yaml /opt/dagster/home/ \
    && cp nginx.conf /etc/nginx/nginx.conf

ENV DAGSTER_HOME=/opt/dagster/home
ENV PYTHONUNBUFFERED=1

EXPOSE 8080

CMD ["./start.sh"]
