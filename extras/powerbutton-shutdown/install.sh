#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo /bin/bash "$0" "$@"
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_SCRIPT="/usr/local/libexec/powerbutton-shutdown.sh"
DEST_PLIST="/Library/LaunchDaemons/com.ideapad.powerbutton-shutdown.plist"

/usr/bin/defaults write /Library/Preferences/com.apple.loginwindow PowerButtonSleepsSystem -bool false

/bin/mkdir -p /usr/local/libexec
/bin/cp "$SCRIPT_DIR/powerbutton-shutdown.sh" "$DEST_SCRIPT"
/usr/sbin/chown root:wheel "$DEST_SCRIPT"
/bin/chmod 0755 "$DEST_SCRIPT"

/bin/cp "$SCRIPT_DIR/com.ideapad.powerbutton-shutdown.plist" "$DEST_PLIST"
/usr/sbin/chown root:wheel "$DEST_PLIST"
/bin/chmod 0644 "$DEST_PLIST"

/bin/launchctl bootout system/com.ideapad.powerbutton-shutdown 2>/dev/null || true
/bin/launchctl bootstrap system "$DEST_PLIST"
/bin/launchctl kickstart -k system/com.ideapad.powerbutton-shutdown

echo "Installed com.ideapad.powerbutton-shutdown."
