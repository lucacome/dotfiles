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

dockutil --add /Applications/Signal.app --after 'Messages' || true
dockutil --add /Applications/Ghostty.app --after 'System Settings' || true
dockutil --add /Applications/zoom.us.app --after 'Ghostty' || true
dockutil --add /System/Applications/Utilities/Activity%20Monitor.app --after 'zoom.us' || true
dockutil --add /Applications/Visual%20Studio%20Code%20-%20Insiders.app --after 'iPhone Mirroring' || true
