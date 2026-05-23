#!/bin/bash
set -euo pipefail

# ----------------------------------------
# Helpers (idempotency utilities)
# ----------------------------------------

brew_install_if_missing() {
  if brew list --cask "$1" >/dev/null 2>&1 || brew list "$1" >/dev/null 2>&1; then
    echo "$1 already installed, skipping."
  else
    brew install --cask "$1" || brew install "$1" || echo "Failed to install $1"
  fi
}

mas_install_if_missing() {
  local id="$1"
  local name="${2:-$id}"

  if mas list | grep -q "^$id "; then
    echo "$name already installed, skipping."
  else
    mas install "$id" || echo "Failed to install $name"
  fi
}

brew_tap_if_missing() {
  if brew tap | grep -q "^$1$"; then
    echo "Tap $1 already added."
  else
    brew tap "$1"
  fi
}

defaults_write_if_needed() {
  local domain="$1"
  local key="$2"
  local value="$3"

  current=$(defaults read "$domain" "$key" 2>/dev/null || true)

  if [[ "$current" == "$value" ]]; then
    echo "$domain $key already set."
  else
    defaults_write_if_needed "$domain" "$key" "$value"
  fi
}

if [[ -z "$TERM" ]]; then
  open -a Terminal "$0"
  exit 0
fi

echo "Checking Full Disk Access for Terminal..."

FDA_TEST="/Library/Application Support/com.apple.TCC/TCC.db"

if ! sudo sqlite3 "$FDA_TEST" "SELECT count(*) FROM access;" >/dev/null 2>&1; then
  echo ""
  echo "======================================="
  echo " Full Disk Access Required"
  echo "======================================="
  echo ""
  echo "1. Enable Full Disk Access for Terminal"
  echo "2. Return here and re-run the script"
  echo ""

  open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

  read -p "Press ENTER after enabling Full Disk Access to exit..."
  exit 1
fi

echo "Full Disk Access confirmed."



# ----------------------------------------
# Permissions
# ----------------------------------------
osascript -e 'tell application "System Events" to get name'
osascript -e 'tell application "Finder" to get name'


# ----------------------------------------
# Enable Touch ID for sudo (macOS)
# ----------------------------------------

PAM_SUDO_FILE="/etc/pam.d/sudo"

if ! grep -q "pam_tid.so" "$PAM_SUDO_FILE"; then
  echo "Enabling Touch ID for sudo..."

  sudo cp "$PAM_SUDO_FILE" "${PAM_SUDO_FILE}.bak"

  if ! grep -q "pam_tid.so" "$PAM_SUDO_FILE"; then
    echo "auth       sufficient     pam_tid.so" | sudo cat - "$PAM_SUDO_FILE" > /tmp/pam_sudo
    sudo mv /tmp/pam_sudo "$PAM_SUDO_FILE"
  fi

  echo "Touch ID enabled."
else
  echo "Touch ID already enabled."
fi

# ----------------------------------------
# Open Settings Panes
# ----------------------------------------

echo "Please configure the following in System Settings:"
echo "- Screenshot shortcuts"
echo "- Control Center"
echo "- Desktop & Dock"
echo "- Wallpaper"

open "x-apple.systempreferences:"

# ----------------------------------------
# Install Homebrew if not present
# ----------------------------------------
if command -v brew >/dev/null 2>&1; then
  echo "Homebrew already installed."
else
  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

SHELL_NAME=$(basename "$SHELL")
APPLE_SILICON="/opt/homebrew"
INTEL="/usr/local"

if [[ -d "$APPLE_SILICON" ]]; then
  BREW_PREFIX="$APPLE_SILICON"
else
  BREW_PREFIX="$INTEL"
fi

case "$SHELL_NAME" in
  zsh) PROFILE="$HOME/.zshrc" ;;
  bash) PROFILE="$HOME/.bash_profile" ;;
  *) PROFILE="$HOME/.profile" ;;
esac

echo ""
echo "Configuring Homebrew PATH in $PROFILE"

if ! grep -q "brew shellenv" "$PROFILE" 2>/dev/null; then
  {
    echo ""
    echo "# Homebrew"
    echo "eval \"\$($BREW_PREFIX/bin/brew shellenv)\""
  } >> "$PROFILE"
  echo "PATH updated."
else
  echo "PATH already configured."
fi

# Load Homebrew for this session
eval "$($BREW_PREFIX/bin/brew shellenv)"

brew update

echo ""
echo "======================================="
echo " Homebrew installation complete!"
echo "======================================="
echo ""

# ----------------------------------------
# Install Privileged Apps FIRST
# ----------------------------------------
echo "Installing privileged apps..."

privileged_apps=(
  auto-subs
  blackhole-2ch
  microsoft-teams
  mas
  shutter-encoder
)

for app in "${privileged_apps[@]}"; do
  echo "Installing $app..."
  brew_install_if_missing "$app"
done

# ----------------------------------------
# Install Rosetta (for Apple Silicon)
# ----------------------------------------
if [[ "$(uname -m)" == "arm64" ]]; then
  echo "Installing Rosetta..."
  softwareupdate --install-rosetta --agree-to-license
fi

# -----------------------------
# Screenshot Directory Change
# -----------------------------

echo ""
echo "Configuring screenshot save location..."

# Create the folder for screenshots (if not already there)
mkdir -p "$HOME/Pictures/Screenshots"

# Set screenshot save location
defaults_write_if_needed com.apple.screencapture location "$HOME/Pictures/Screenshots"

echo "Screenshot save location set to ~/Pictures/Screenshots."

# ----------------------------------------
# Configure Screenshot Keyboard Shortcuts
# ----------------------------------------
echo "Configuring screenshot keyboard shortcuts..."

# Save selected area as file → CMD+SHIFT+3
defaults_write_if_needed com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 28 "
<dict>
  <key>enabled</key><true/>
  <key>value</key>
  <dict>
    <key>parameters</key>
    <array>
      <integer>51</integer>
      <integer>20</integer>
      <integer>1179648</integer>
    </array>
    <key>type</key><string>standard</string>
  </dict>
</dict>"

# Copy selected area to clipboard → CMD+SHIFT+4
defaults_write_if_needed com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 30 "
<dict>
  <key>enabled</key><true/>
  <key>value</key>
  <dict>
    <key>parameters</key>
    <array>
      <integer>52</integer>
      <integer>21</integer>
      <integer>1179648</integer>
    </array>
    <key>type</key><string>standard</string>
  </dict>
</dict>"

# Disable:
# Save whole screen as file
defaults_write_if_needed com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 29 "
<dict>
  <key>enabled</key><false/>
</dict>"

# Copy whole screen to clipboard
defaults_write_if_needed com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 31 "
<dict>
  <key>enabled</key><false/>
</dict>"

# Disable Spotlight shortcut (CMD+SPACE)
defaults_write_if_needed com.apple.symbolichotkeys AppleSymbolicHotKeys -dict-add 64 "
<dict>
  <key>enabled</key><false/>
</dict>"

echo "Screenshot and Spotlight shortcuts configured."

# -----------------------------
# Finder Settings
# -----------------------------
echo "Configuring Finder preferences..."

# Show all filename extensions
defaults_write_if_needed NSGlobalDomain AppleShowAllExtensions -bool true

# Set Finder search to current folder by default
defaults_write_if_needed com.apple.finder FXDefaultSearchScope -string "SCcf"

# Set new Finder windows to open Downloads folder
defaults_write_if_needed com.apple.finder NewWindowTarget -string "PfLo"
defaults_write_if_needed com.apple.finder NewWindowTargetPath -string "file://${HOME}/Downloads/"

defaults_write_if_needed com.apple.finder ShowPathbar -bool true
defaults_write_if_needed com.apple.finder ShowStatusBar -bool true

echo "Finder preferences configured."

# ----------------------------------------
# Configure Finder Sidebar
# ----------------------------------------
echo "Configuring Finder sidebar..."

# Hide Recents
defaults_write_if_needed com.apple.finder ShowRecentTags -bool false
defaults_write_if_needed com.apple.finder FXRemoveOldTrashItems -bool true

# Sidebar items
defaults_write_if_needed com.apple.sidebarlists systemitems -dict-add ShowAirDrop -bool false
defaults_write_if_needed com.apple.sidebarlists systemitems -dict-add ShowBonjour -bool false
defaults_write_if_needed com.apple.sidebarlists systemitems -dict-add ShowConnectedServers -bool false

# Remove shared section
defaults_write_if_needed com.apple.finder SidebarSharedSectionDisclosedState -bool false

# Remove recent tags
defaults_write_if_needed com.apple.finder ShowRecentTags -bool false

# Hide sidebar tags section entirely
defaults_write_if_needed com.apple.finder FXTagsEnabled -bool false

echo "Finder settings configured"

# -----------------------------
# TextEdit Preferences
# -----------------------------
echo "Configuring TextEdit to open plain text by default..."

defaults_write_if_needed com.apple.TextEdit NSShowAppCentricOpenPanelInsteadOfUntitledFile -bool false
defaults_write_if_needed com.apple.TextEdit RichText -int 0
defaults_write_if_needed com.apple.TextEdit PlainTextEncoding -int 4
defaults_write_if_needed com.apple.TextEdit PlainTextEncodingForWrite -int 4

echo "TextEdit preferences configured."

# -----------------------------
# Dock Settings
# -----------------------------
echo "Configuring Dock settings..."

# Enable magnification
defaults_write_if_needed com.apple.dock magnification -bool true
defaults_write_if_needed com.apple.dock largesize -int 64

# Enable auto-hide
defaults_write_if_needed com.apple.dock autohide -bool true

# Make Dock Faster
defaults_write_if_needed com.apple.dock autohide-delay -int 0
defaults_write_if_needed com.apple.dock autohide-time-modifier -float 0.5

# Remove all apps from dock
defaults_write_if_needed com.apple.dock persistent-apps -array

# Disable "Show suggested and recent apps in Dock"
defaults_write_if_needed com.apple.dock show-recents -bool false

# -----------------------------
# Disable Mission Control & App Expose
# -----------------------------

defaults_write_if_needed com.apple.dock showMissionControlGestureEnabled -bool false
defaults_write_if_needed com.apple.dock showAppExposeGestureEnabled -bool false

echo "Dock settings applied."

# -----------------------------
# Change Spelling Settings
# -----------------------------

echo "Disabling macOS autocorrect and automatic capitalization..."

# Disable automatic spelling correction
defaults_write_if_needed NSGlobalDomain NSAutomaticSpellingCorrectionEnabled -bool false

# Disable autocapitalization
defaults_write_if_needed NSGlobalDomain NSAutomaticCapitalizationEnabled -bool false

# Disable smart quotes and dashes
defaults_write_if_needed NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults_write_if_needed NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

echo "Autocorrect, spelling correction, and capitalization disabled."

echo ""
echo "Spelling Settings applied."

# -----------------------------
# Miscellaneous Settings
# -----------------------------
defaults_write_if_needed com.apple.controlcenter BatteryShowPercentage -bool true
defaults_write_if_needed com.apple.loginwindow TALLogoutSavesState -bool false
defaults_write_if_needed com.apple.coreservices.uiagent CSUIShowCloudSetupDialogs -bool false
defaults_write_if_needed NSGlobalDomain NSWindowResizeTime -float 0.001
defaults_write_if_needed com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true

# -----------------------------
# Apply settings
# -----------------------------
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
killall ControlCenter 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true
killall TextEdit 2>/dev/null || true

echo "All settings applied!"
# ----------------------------------------
# Tap custom Homebrew repo
# ----------------------------------------
echo ""
echo "Tapping MasterofDeath01/apps..."
brew_tap_if_missing "MasterofDeath01/apps"

# ----------------------------------------
# Install custom apps & fonts
# ----------------------------------------
echo "Installing custom apps and fonts..."

custom_casks=(
  adobe-activation-tool
  topaz-video-enhance-ai
  cleanmymacx
  adobe-downloader
  altone-trial-bold-oblique
  altone-trial-bold
  altone-trial-oblique
  altone-trial-regular
  charlie-dont-surf
  daughter-of-fortune
  designer
  harry-p
  iron-man-of-war
  kromika-axis
  lemonmilk-bold-italic
  lemonmilk-bold
  lemonmilk-light-italic
  lemonmilk-light
  lemonmilk-medium-italic
  lemonmilk-medium
  lemonmilk-regular-italic
  lemonmilk-regular
  luminance-smallcaps
  pieces-of-eight
  signatra
  sylfaen
  utsaah
  the-amazing-spider-man
  mister-horse-product-manager
  vencord-installer
  zxp-installer
  compacta
)

for cask in "${custom_casks[@]}"; do
  echo "Installing $cask..."
  brew_install_if_missing "$cask"
done 


# ----------------------------------------
# Install Normal Apps
# ----------------------------------------
echo "Installing normal apps..."

normal_apps=(
  lookaway
  nvidia-geforce-now
  finetune
  impactor
  onyx
  chatgpt
  surfshark
  raycast
  betterdisplay
  modrinth
  google-chrome
  mediamate
  clipgrab
  middle
  adobe-creative-cloud-cleaner-tool
  spotify
  audacity
  keka
  discord
  blender
  calibre
  claude
  firefox
  handbrake
  vlc
  iina
  visual-studio-code
  krita
  pinta
  macs-fan-control
  appcleaner
  upscayl
  latest
  mos
  keyboardcleantool
  roblox
  capcut
  imageoptim
  mkvtoolnix
  macusb
  codeforreal1/tap/compresso
)

for app in "${normal_apps[@]}"; do
  echo "Installing $app..."

  brew_install_if_missing "$app"

# ----------------------------------------
# Install Fonts
# ----------------------------------------
echo "Installing fonts..."
fonts=(
  font-baloo-2
  font-bebas-neue
  font-beau-rivage
  font-courgette
  font-courier-new
  font-courier-prime
  font-courier-prime-code
  font-nunito
  font-comfortaa
)

for font in "${fonts[@]}"; do
  echo "Installing $font..."

brew_install_if_missing "$app"

echo ""
echo "======================================="
echo "Installing Mac App Store apps via mas"
echo "======================================="

mas_apps=(
  310633997  # WhatsApp Messenger
  6698876601 # Folder Preview
  6745342698 # Ublock Origin Lite
  1592917505 # Noir - Dark Mode for Safari
  510620098  # MediaInfo
  1448916662 # Step Two
  1355679052 # Dropover
  784801555  # Microsoft OneNote
  462054704  # Microsoft Word
  462058435  # Microsoft Excel
  462062816  # Microsoft PowerPoint
  823766827  # OneDrive
  985367838  # Microsoft Outlook
  
)

for app_id in "${mas_apps[@]}"; do
  echo "Installing MAS app $app_id…"
  mas_install_if_missing "$app_id"
done

# ----------------------------------------
# Xattr Apps
# ----------------------------------------

sudo xattr -cr /Applications/Mos.app
sudo xattr -cr /Applications/'CleanMyMac X.app'
sudo xattr -cr /Applications/'Topaz Video.app'
sudo xattr -cr /Applications/'Adobe Downloader.app'
sudo xattr -cr /Applications/Adobe\ Activation\ Tool.app

# ----------------------------------------
# Launch Installed Apps
# ----------------------------------------

echo ""
echo "Opening selected apps..."

apps_to_open=(
  "LookAway"
  "BetterDisplay"
  "Mos"
  "CleanMyMac X"
  "OneDrive"
  "MediaMate"
  "Dropover"
  "Macs Fan Control"
  "Folder Preview"
  "Raycast"
  "Middle"
)

for app in "${apps_to_open[@]}"; do
  echo "Opening $app..."
  open -a "$app" 2>/dev/null || echo "$app not installed or failed to open"
done


echo ""
echo "======================================="
echo " Setup complete!"
echo "======================================="

osascript -e 'tell app "System Events" to display dialog "Setup Complete!"'

read -n 1 -s -r -p "Press any key to close…"
