#!/usr/bin/env bash
set -Eeuo pipefail

# Параметры (могут переопределяться через EnvironmentFile= в systemd)
PROC_NAME="${PROC_NAME:-test}"
MONITOR_URL="${MONITOR_URL:-https://test.com/monitoring/test/api}"

STATE_DIR="${STATE_DIR:-/var/lib/test-monitor}"
STATE_FILE="${STATE_FILE:-$STATE_DIR/state}"
LOG_FILE="${LOG_FILE:-/var/log/monitoring.log}"
LOCK_FILE="${LOCK_FILE:-/run/lock/test-monitor.lock}"

# Подготовка окружения
mkdir -p "$STATE_DIR"
touch "$LOG_FILE"
chmod 0644 "$LOG_FILE"

# Блокируем параллельные запуски
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  exit 0
fi

timestamp() { date '+%Y-%m-%d %H:%M:%S%z'; }
log() { echo "$(timestamp) $*" >> "$LOG_FILE"; }

# Ищем процесс по точному имени (если их несколько — берём самый старый PID)
pid="$(pgrep -xo "$PROC_NAME" || true)"
if [[ -z "$pid" ]]; then
  # Процесс не запущен — ничего не делаем
  exit 0
fi

stat_file="/proc/$pid/stat"
if [[ ! -r "$stat_file" ]]; then
  exit 0
fi

# Поле 22 — starttime (jiffies с момента boot)
start_jiffies="$(awk '{print $22}' "$stat_file" 2>/dev/null || true)"
if [[ -z "$start_jiffies" ]]; then
  exit 0
fi

current_boot_id="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo "unknown")"

prev_boot_id=""
prev_pid=""
prev_start=""

if [[ -f "$STATE_FILE" ]]; then
  prev_boot_id="$(grep -E '^boot_id=' "$STATE_FILE" | head -n1 | cut -d'=' -f2- || true)"
  prev_pid="$(grep -E '^pid=' "$STATE_FILE" | head -n1 | cut -d'=' -f2- || true)"
  prev_start="$(grep -E '^starttime=' "$STATE_FILE" | head -n1 | cut -d'=' -f2- || true)"
fi

# Перезапуск процесса = тот же boot_id, но starttime изменился
if [[ -n "$prev_start" && "$prev_boot_id" == "$current_boot_id" && "$prev_start" != "$start_jiffies" ]]; then
  log "process '$PROC_NAME' restarted (old pid=$prev_pid starttime=$prev_start -> new pid=$pid starttime=$start_jiffies)"
fi

# Обновляем состояние
printf 'boot_id=%s\npid=%s\nstarttime=%s\n'       "$current_boot_id" "$pid" "$start_jiffies" > "$STATE_FILE"
chmod 0640 "$STATE_FILE"

# Пингуем мониторинг (успех — молча; ошибка — в лог)
if ! curl -sSf -m 10 -A "test-monitor/1.0 ($(hostname -f 2>/dev/null || hostname))"          "$MONITOR_URL" >/dev/null; then
  rc=$?
  log "monitoring server unreachable (curl exit=$rc) url=$MONITOR_URL"
fi
