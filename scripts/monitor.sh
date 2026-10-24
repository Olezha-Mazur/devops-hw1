#!/usr/bin/env bash

set -uo pipefail

usage() {
  echo "Usage: $0 <systemd-service>" >&2
  exit 64
}

[[ $# -eq 1 ]] || usage
service="$1"

if [[ ! "$service" =~ ^[a-zA-Z0-9_.@-]+$ ]]; then
  echo "Invalid service name: $service" >&2
  exit 64
fi

if ! command -v systemctl >/dev/null; then
  echo "systemctl is unavailable: run this script on a systemd-based Linux host." >&2
  exit 69
fi

echo "== Service: $service =="
if ! systemctl cat "$service" >/dev/null 2>&1; then
  echo "Service '$service' was not found." >&2
  exit 3
fi

status="$(systemctl is-active "$service" 2>&1 || true)"
echo "Status: $status"
if [[ "$status" != "active" ]]; then
  echo "-- Last 10 journal lines --"
  journalctl --no-pager -u "$service" -n 10 2>&1 || true
fi

syslog_file="${SYSLOG_FILE:-/var/log/syslog}"
echo "-- Errors in $syslog_file during the last hour --"
if [[ ! -r "$syslog_file" ]]; then
  echo "Log file is not readable (try sudo or set SYSLOG_FILE to a readable file)." >&2
  exit 0
fi

{ grep -E -i 'error|failed|critical' "$syslog_file" || true; } | awk '
BEGIN {
  split("Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec", names, " ")
  for (i = 1; i <= 12; i++) month[names[i]] = i
  now = systime(); cutoff = now - 3600; year = strftime("%Y", now)
}
{
  if (!($1 in month) || $2 !~ /^[0-9]+$/ || $3 !~ /^[0-9]{2}:[0-9]{2}:[0-9]{2}$/) next
  split($3, clock, ":")
  timestamp = mktime(sprintf("%d %02d %02d %02d %02d %02d", year, month[$1], $2, clock[1], clock[2], clock[3]))
  if (timestamp > now + 86400) timestamp = mktime(sprintf("%d %02d %02d %02d %02d %02d", year - 1, month[$1], $2, clock[1], clock[2], clock[3]))
  if (timestamp >= cutoff && timestamp <= now) count++
}
END { print "Count: " (count + 0) }
'
