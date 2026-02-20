#!/bin/bash

set -eufo pipefail

defaults write -g AppleMiniaturizeOnDoubleClick -int 0
defaults write -g ApplePressAndHoldEnabled -int 0
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

defaults write -g com.apple.trackpad.forceClick -int 1

defaults write com.apple.dock autohide -int 1
defaults write com.apple.dock orientation -string left

defaults write -g NSGlassDiffusionSetting 1

defaults write com.apple.finder FXPreferredViewStyle -string Nlsv
defaults write com.apple.finder FXEnableExtensionChangeWarning -int 0

defaults write com.apple.spaces spans-displays -int 1 && killall SystemUIServer
