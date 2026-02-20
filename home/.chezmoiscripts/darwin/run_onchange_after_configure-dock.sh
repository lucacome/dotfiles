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
