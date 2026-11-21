#!/bin/bash
export LC_ALL=C

LOG_FILE="/var/log/ws-priority-guard.log"
SLEEP_PID=""
IN_GUARD=0
IDLE_STREAK=0

cleanup() {
  if [ -n "$SLEEP_PID" ]; then
    kill "$SLEEP_PID" 2>/dev/null || true
  fi
  exit 0
}
trap cleanup TERM INT

log_msg() {
  if [ -f "$LOG_FILE" ]; then
    local lines
    lines=$(/usr/bin/wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    lines="${lines// /}"
    if [ "${lines:-0}" -gt 300 ] 2>/dev/null; then
      /usr/bin/tail -n 150 "$LOG_FILE" > "${LOG_FILE}.tmp" 2>/dev/null && \
        /bin/cat "${LOG_FILE}.tmp" > "$LOG_FILE" 2>/dev/null && \
        /bin/rm -f "${LOG_FILE}.tmp"
    fi
  fi
  printf '[%s] %s\n' "$(/bin/date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG_FILE"
}

set_nice() {
  local pid="$1" cur_ni="$2" target_ni="$3" label="$4"
  if [ "$cur_ni" != "$target_ni" ]; then
    if /usr/bin/renice "$target_ni" -p "$pid" >/dev/null 2>&1; then
      log_msg "$label (pid=$pid) nice: $cur_ni -> $target_ni"
      return 0
    else
      log_msg "WARN: renice $target_ni failed for $label (pid=$pid)"
      return 1
    fi
  fi
  return 0
}

throttle_bg_hog() {
  local pid="$1" cur_ni="$2" label="$3"
  if [ "$cur_ni" != "19" ]; then
    /usr/sbin/taskpolicy -b -p "$pid" >/dev/null 2>&1 || true
    set_nice "$pid" "$cur_ni" 19 "$label (bg+taskpolicy)"
  fi
}

log_msg "ws-priority-guard started (pid=$$)"

while true; do
  SNAP=$(/bin/ps -axo pid=,ni=,%cpu=,comm= 2>/dev/null || true)
  if [ -n "$SNAP" ]; then
    PARSED=$(printf '%s\n' "$SNAP" | /usr/bin/awk '
      BEGIN { active = 0; cnt = 0 }
      NF >= 4 {
        pid = $1;
        ni = $2;
        cpu = $3 + 0;
        cmd = $0;
        sub(/^[[:space:]]*[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/, "", cmd);
        n = split(cmd, parts, "/");
        base = parts[n];

        if ((base == "replayd" && cpu >= 1.5) ||
            (base == "VTEncoderXPCService" && cpu >= 5.0) ||
            (base == "WhatsApp" && cpu >= 18.0)) {
          active = 1;
        }

        if (base == "WindowServer" ||
            base == "VTEncoderXPCService" ||
            base == "VTDecoderXPCService" ||
            base == "WhatsApp" ||
            base == "icloudmailagent" ||
            base == "mds_stores" ||
            base == "photoanalysisd" ||
            base == "mediaanalysisd" ||
            base == "spotlightknowledged") {
          cnt++;
          cpu_ge_50 = (cpu >= 50.0) ? 1 : 0;
          rows[cnt] = "PROC|" pid "|" ni "|" cpu_ge_50 "|" base;
        }
      }
      END {
        printf "STATE|%d\n", active;
        for (i = 1; i <= cnt; i++) {
          print rows[i];
        }
      }
    ')

    RESTORE_NOW=0
    while IFS='|' read -r kind f1 f2 f3 f4; do
      if [ "$kind" = "STATE" ]; then
        if [ "$f1" -eq 1 ]; then
          IDLE_STREAK=0
          if [ "$IN_GUARD" -eq 0 ]; then
            IN_GUARD=1
            log_msg "Screen-share/call active; guard enabled"
          fi
        else
          if [ "$IN_GUARD" -eq 1 ]; then
            IDLE_STREAK=$((IDLE_STREAK + 1))
            if [ "$IDLE_STREAK" -ge 3 ]; then
              IN_GUARD=0
              IDLE_STREAK=0
              RESTORE_NOW=1
              log_msg "Screen-share/call idle; restoring encoder/app nice values"
            fi
          fi
        fi
        continue
      fi

      [ "$kind" = "PROC" ] || continue
      pid="$f1"
      ni="$f2"
      cpu_ge_50="$f3"
      base="$f4"

      case "$ni" in
        ''|*[!0-9-]*) continue ;;
      esac

      case "$base" in
        WindowServer)
          set_nice "$pid" "$ni" -12 "WindowServer"
          ;;
        VTEncoderXPCService)
          if [ "$IN_GUARD" -eq 1 ]; then
            set_nice "$pid" "$ni" 8 "VTEncoderXPCService"
          elif [ "$RESTORE_NOW" -eq 1 ] && [ "$ni" -gt 0 ]; then
            set_nice "$pid" "$ni" 0 "VTEncoderXPCService"
          fi
          ;;
        VTDecoderXPCService)
          if [ "$IN_GUARD" -eq 1 ]; then
            set_nice "$pid" "$ni" 4 "VTDecoderXPCService"
          elif [ "$RESTORE_NOW" -eq 1 ] && [ "$ni" -gt 0 ]; then
            set_nice "$pid" "$ni" 0 "VTDecoderXPCService"
          fi
          ;;
        WhatsApp)
          if [ "$IN_GUARD" -eq 1 ]; then
            set_nice "$pid" "$ni" 6 "WhatsApp"
          elif [ "$RESTORE_NOW" -eq 1 ] && [ "$ni" -gt 0 ]; then
            set_nice "$pid" "$ni" 0 "WhatsApp"
          fi
          ;;
        icloudmailagent)
          if [ "$IN_GUARD" -eq 1 ] || [ "$cpu_ge_50" -eq 1 ]; then
            throttle_bg_hog "$pid" "$ni" "icloudmailagent"
          fi
          ;;
        mds_stores|photoanalysisd|mediaanalysisd|spotlightknowledged)
          if [ "$IN_GUARD" -eq 1 ]; then
            throttle_bg_hog "$pid" "$ni" "$base"
          fi
          ;;
      esac
    done <<< "$PARSED"
  fi

  /bin/sleep 4 &
  SLEEP_PID=$!
  wait "$SLEEP_PID" 2>/dev/null || true
  SLEEP_PID=""
done
