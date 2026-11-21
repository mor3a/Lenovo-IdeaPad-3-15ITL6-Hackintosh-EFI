#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo /bin/bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_SCRIPT="/usr/local/libexec/ws-priority-guard.sh"
DEST_PLIST="/Library/LaunchDaemons/com.ideapad.screenshare-priority.plist"

/bin/mkdir -p /usr/local/libexec
/bin/cp "$SCRIPT_DIR/ws-priority-guard.sh" "$DEST_SCRIPT"
/usr/sbin/chown root:wheel "$DEST_SCRIPT"
/bin/chmod 0755 "$DEST_SCRIPT"

/bin/cp "$SCRIPT_DIR/com.ideapad.screenshare-priority.plist" "$DEST_PLIST"
/usr/sbin/chown root:wheel "$DEST_PLIST"
/bin/chmod 0644 "$DEST_PLIST"

/bin/launchctl bootout system/com.ideapad.screenshare-priority 2>/dev/null || true
/bin/launchctl bootstrap system "$DEST_PLIST"
/bin/launchctl kickstart -k system/com.ideapad.screenshare-priority

echo "Installed com.ideapad.screenshare-priority."
