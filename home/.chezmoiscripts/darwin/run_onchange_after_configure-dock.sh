#!/bin/bash

set -eufo pipefail

trap 'killall Dock' EXIT

declare -a remove_labels=(
    Calendar
    Contacts
    FaceTime
    Freeform
    Keynote
    Mail
    Maps
    Music
    News
    Numbers
    Pages
    Photos
    Reminders
    TV
)

for label in "${remove_labels[@]}"; do
	dockutil --no-restart --remove "${label}" || true
done

dockutil --no-restart --add /Applications/Signal.app --after 'Messages' || true
dockutil --no-restart --add /Applications/Ghostty.app --after 'System Settings' || true
dockutil --no-restart --add /Applications/zoom.us.app --after 'Ghostty' || true
dockutil --no-restart --add '/System/Applications/Utilities/Activity Monitor.app' --after 'zoom.us' || true
dockutil --no-restart --add '/Applications/Visual Studio Code - Insiders.app' --after 'iPhone Mirroring' || true
