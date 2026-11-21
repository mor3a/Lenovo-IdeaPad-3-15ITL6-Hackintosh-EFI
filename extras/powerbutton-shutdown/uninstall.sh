#!/bin/bash
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  exec sudo /bin/bash "$0" "$@"
fi

/bin/launchctl bootout system/com.ideapad.powerbutton-shutdown 2>/dev/null || true
/bin/rm -f /Library/LaunchDaemons/com.ideapad.powerbutton-shutdown.plist
/bin/rm -f /usr/local/libexec/powerbutton-shutdown.sh
/usr/bin/defaults delete /Library/Preferences/com.apple.loginwindow PowerButtonSleepsSystem 2>/dev/null || true

echo "Removed com.ideapad.powerbutton-shutdown and restored PowerButtonSleepsSystem."
