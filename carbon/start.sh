#!/bin/sh
set -eu

if [ -z "${DAGSTER_BASIC_AUTH_USER:-}" ] || [ -z "${DAGSTER_BASIC_AUTH_PASSWORD:-}" ]; then
  echo "DAGSTER_BASIC_AUTH_USER and DAGSTER_BASIC_AUTH_PASSWORD are required" >&2
  exit 1
fi

mkdir -p /data/dagster/artifacts /data/dagster/compute_logs "${DAGSTER_HOME:-/opt/dagster/home}/logs"
htpasswd -bc /etc/nginx/.htpasswd "$DAGSTER_BASIC_AUTH_USER" "$DAGSTER_BASIC_AUTH_PASSWORD"

dagster-webserver -h 127.0.0.1 -p 3000 &
web_pid=$!

i=0
while ! python3 -c "import socket; socket.create_connection(('127.0.0.1', 3000), 1).close()" 2>/dev/null; do
  if ! kill -0 "$web_pid" 2>/dev/null; then
    echo "dagster-webserver exited before binding port 3000" >&2
    exit 1
  fi
  i=$((i + 1))
  if [ "$i" -gt 90 ]; then
    echo "timed out waiting for dagster-webserver on :3000" >&2
    exit 1
  fi
  sleep 1
done

dagster-daemon run &

# Schedules stay STOPPED in the instance DB unless started. Keep the daily
# carbon job on across restarts even if it was first loaded as stopped.
(
  i=0
  while [ "$i" -lt 30 ]; do
    if dagster schedule start daily_us_carbon_schedule >/tmp/pulse-carbon-schedule.log 2>&1; then
      echo "started daily_us_carbon_schedule" >&2
      break
    fi
    if grep -qiE 'already running|already started' /tmp/pulse-carbon-schedule.log; then
      break
    fi
    i=$((i + 1))
    sleep 2
  done
) &

nginx
wait "$web_pid"
