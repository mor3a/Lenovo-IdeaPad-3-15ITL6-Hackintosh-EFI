#!/bin/bash
export LC_ALL=C

LOG_FILE="/var/log/powerbutton-shutdown.log"
FIFO="/tmp/powerbutton-shutdown.$$.fifo"
LOG_PID=""
TRIGGERED=0

MATCH_RE='^20[0-9]{2}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+ Df loginwindow\[[0-9]+:[0-9a-fA-F]+\].*kPowerButtonHotKeyID event - calling handlePowerButtonEvent:YES'

is_power_button_down() {
  case "$1" in
    Filtering*|Timestamp*|"") return 1 ;;
  esac
  if [[ "$1" =~ $MATCH_RE ]]; then
    return 0
  fi
  return 1
}

run_selftest() {
  local line
  local pass=1

  line='Filtering the log data using "process == \"loginwindow\" AND subsystem == \"com.apple.loginwindow.logging\" AND eventMessage CONTAINS \"kPowerButtonHotKeyID event\""'
  if is_power_button_down "$line"; then
    echo "FAIL: Filtering header falsely matched"
    pass=0
  fi

  line='Timestamp               Ty Process[PID:TID]'
  if is_power_button_down "$line"; then
    echo "FAIL: Timestamp header falsely matched"
    pass=0
  fi

  line='2026-11-21 03:28:06.464 Df loginwindow[211:37d] [com.apple.loginwindow.logging:Standard] -[HotKeyManager handleSystemEvent:] | calling handlePowerButtonEvent:NO'
  if is_power_button_down "$line"; then
    echo "FAIL: keyUP falsely matched"
    pass=0
  fi

  line='2026-11-21 03:28:06.402 Df loginwindow[211:37d] [com.apple.loginwindow.logging:Standard] -[HotKeyManager handleSystemEvent:] | kPowerButtonHotKeyID event - calling handlePowerButtonEvent:YES'
  if ! is_power_button_down "$line"; then
    echo "FAIL: valid kPowerButtonHotKeyID down event did NOT match"
    pass=0
  fi

  if [ "$pass" -eq 1 ]; then
    echo "PASS: all 4 selftest cases passed"
    return 0
  fi
  return 1
}

if [ "${1:-}" = "--selftest" ]; then
  run_selftest
  exit $?
fi

cleanup() {
  if [ -n "$LOG_PID" ]; then
    kill "$LOG_PID" 2>/dev/null || true
    wait "$LOG_PID" 2>/dev/null || true
    LOG_PID=""
  fi
  /bin/rm -f "$FIFO" 2>/dev/null || true
}

on_signal() {
  cleanup
  exit 0
}
trap on_signal TERM INT
trap cleanup EXIT

log_msg() {
  if [ -f "$LOG_FILE" ]; then
    local lines
    lines=$(/usr/bin/wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    lines="${lines// /}"
    if [ "${lines:-0}" -gt 200 ] 2>/dev/null; then
      /usr/bin/tail -n 100 "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null && \
        /bin/cat "${LOG_FILE}.tmp" > "$LOG_FILE" 2>/dev/null && \
        /bin/rm -f "${LOG_FILE}.tmp"
    fi
  fi
  printf '[%s] %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

log_msg "powerbutton-shutdown started (pid=$$)"

while true; do
  /bin/rm -f "$FIFO" 2>/dev/null || true
  if ! /usr/bin/mkfifo -m 0600 "$FIFO"; then
    log_msg "ERROR: mkfifo failed for $FIFO; retrying in 5s"
    /bin/sleep 5
    continue
  fi

  /usr/bin/log stream --style compact --predicate 'process == "loginwindow" AND subsystem == "com.apple.loginwindow.logging" AND eventMessage CONTAINS "kPowerButtonHotKeyID event"' > "$FIFO" 2>/dev/null &
  LOG_PID=$!

  while IFS= read -r line; do
    if is_power_button_down "$line"; then
      if [ "$TRIGGERED" -eq 0 ]; then
        TRIGGERED=1
        log_msg "Power button pressed (loginwindow kPowerButtonHotKeyID) -> running /sbin/shutdown -h now"
        /sbin/shutdown -h now >/dev/null 2>&1 || true
        /bin/sleep 30
      fi
    fi
  done < "$FIFO"

  cleanup
  if [ "$TRIGGERED" -eq 0 ]; then
    log_msg "log stream exited unexpectedly; reconnecting in 2s"
    /bin/sleep 2
  else
    /bin/sleep 5
  fi
done
