#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo /bin/bash "$0" "$@"
fi

/bin/launchctl bootout system/com.ideapad.screenshare-priority 2>/dev/null || true
/bin/rm -f /Library/LaunchDaemons/com.ideapad.screenshare-priority.plist
/bin/rm -f /usr/local/libexec/ws-priority-guard.sh

for name in WindowServer WhatsApp VTEncoderXPCService VTDecoderXPCService; do
  pids=$(/usr/bin/pgrep -x "$name" 2>/dev/null || true)
  for p in $pids; do
    /usr/bin/renice 0 -p "$p" >/dev/null 2>&1 || true
  done
done

echo "Removed com.ideapad.screenshare-priority and reset nice values."
