#!/bin/bash

set -eufo pipefail

defaults write -g AppleMiniaturizeOnDoubleClick -int 0
defaults write -g ApplePressAndHoldEnabled -int 0
defaults write -g AppleKeyboardUIMode -int 2
defaults write -g AppleShowAllExtensions -int 1
defaults write -g InitialKeyRepeat -int 15
defaults write -g KeyRepeat -int 2
defaults write -g NSAutomaticCapitalizationEnabled -int 0
defaults write -g NSAutomaticDashSubstitutionEnabled -int 0
defaults write -g NSAutomaticInlinePredictionEnabled -int 0
defaults write -g NSAutomaticPeriodSubstitutionEnabled -int 0
defaults write -g NSAutomaticQuoteSubstitutionEnabled -int 0
defaults write -g NSAutomaticSpellingCorrectionEnabled -int 0
defaults write -g NSAutomaticTextCompletionEnabled -int 0
defaults write -g NSAutomaticWindowAnimationsEnabled -int 0
defaults write -g WebAutomaticSpellingCorrectionEnabled -int 0
defaults write -g NSWindowShouldDragOnGesture -int 1

# disable lookup
defaults write -g com.apple.trackpad.forceClick -int 0

# dock
defaults write com.apple.dock autohide -int 1
defaults write com.apple.dock autohide-time-modifier -float 0
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock orientation -string left
defaults write com.apple.dock tilesize -int 42
defaults write com.apple.dock expose-group-apps -int 1
defaults write com.apple.dock mru-spaces -int 0

defaults write -g NSGlassDiffusionSetting 1

# finder
defaults write com.apple.finder FXPreferredViewStyle -string Nlsv
defaults write com.apple.finder FXEnableExtensionChangeWarning -int 0
defaults write com.apple.finder QuitMenuItem -int 1
defaults write com.apple.finder ShowPathbar -int 1
defaults write com.apple.finder ShowStatusBar -int 1
defaults write com.apple.finder _FXSortFoldersFirst -int 1
defaults write com.apple.finder FinderSpawnTab -int 0

defaults write NSGlobalDomain AppleSpacesSwitchOnActivate -int 0
defaults write com.apple.spaces spans-displays -int 1

killall SystemUIServer && killall Dock && killall Finder

# disable spotlight
defaults write com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 "<dict><key>enabled</key><false/><key>value</key><dict><key>parameters</key><array><integer>32</integer><integer>49</integer><integer>1048576</integer></array><key>type</key><string>standard</string></dict></dict>"

/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
