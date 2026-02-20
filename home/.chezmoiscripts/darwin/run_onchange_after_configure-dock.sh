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

dockutil --add /Applications/Signal.app --after 'Messages'
dockutil --add /Applications/Ghostty.app --after 'System Settings'
dockutil --add /Applications/zoom.us.app --after 'Ghostty'
dockutil --add /System/Applications/Utilities/Activity%20Monitor.app --after 'zoom.us'
dockutil --add /Applications/Visual%20Studio%20Code%20-%20Insiders.app --after 'iPhone Mirroring'
