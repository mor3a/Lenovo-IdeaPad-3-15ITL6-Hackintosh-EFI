#!/bin/bash
set -euo pipefail

# Disable hardware H.264/HEVC encoding fallback in AppleGVA and force software FaceTime
# encoder/decoder to avoid Tiger Lake VCS0 GPU freezes during video calls.
/usr/bin/defaults write com.apple.AppleGVA disableVDENC -bool true
/usr/bin/defaults write com.apple.VideoConference FaceTimeEncoder -string sw
/usr/bin/defaults write com.apple.VideoConference FaceTimeDecoder -string sw
/bin/launchctl kickstart -k "gui/$(id -u)/com.apple.videoconference.camera" 2>/dev/null || true

echo "Video call stability fixes applied. Restart FaceTime/WhatsApp (or reboot) to take effect."
