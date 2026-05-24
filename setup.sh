#!/bin/bash
set -euo pipefail

# ----------------------------------------
# Helpers (idempotency utilities)
# ----------------------------------------

brew_install_if_missing() {
  local name="$1"

  if brew list --formula "$name" >/dev/null 2>&1 || \
     brew list --cask "$name" >/dev/null 2>&1; then
    echo "$name already installed, skipping."
    return 0
  fi

  if brew install --cask "$name" 2>/dev/null; then
    echo "Installed cask: $name"
  elif brew install "$name" 2>/dev/null; then
    echo "Installed formula: $name"
  else
    echo "Failed to install $name"
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
  local domain="${1:-}"
  local key="${2:-}"
  local type="${3:-}"
  local value="${4:-}"

  if [[ -z "$domain" || -z "$key" || -z "$type" || -z "$value" ]]; then
    echo "ERROR: defaults_write_if_needed requires 4 args: domain key type value"
    echo "Got: $*"
    return 1
  fi

  local current
  current=$(defaults read "$domain" "$key" 2>/dev/null || echo "__MISSING__")

  case "$type" in
    -bool)
      [[ "$current" == "1" ]] && current="true"
      [[ "$current" == "0" ]] && current="false"
      ;;
  esac

  if [[ "$current" == "$value" ]]; then
    echo "$domain $key already set."
  else
    defaults write "$domain" "$key" "$type" "$value"
    echo "Updated $domain $key"
  fi
}

require_full_disk_access() {
  echo "Checking Full Disk Access..."
  local tcc_db="$HOME/Library/Application Support/com.apple.TCC/TCC.db"
  if ! sqlite3 "$tcc_db" ".tables" >/dev/null 2>&1; then
    osascript <<EOF
display dialog "Terminal needs Full Disk Access.\n\nEnable it in:\nSystem Settings → Privacy & Security → Full Disk Access\n\nThen FULLY QUIT Terminal and re-run the script." buttons {"Open Settings"} default button 1 with icon caution
EOF
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
  sleep 1
    osascript -e 'tell application "Terminal" to quit'

exit 1
  fi
  echo "Full Disk Access confirmed."
}

require_accessibility() {
  echo "Checking Accessibility permission..."
  local access_test
  access_test=$(osascript <<EOF
tell application "System Events"
  try
    get name of every process
    return "OK"
  on error
    return "DENIED"
  end try
end tell
EOF
)
  if [[ "$access_test" != "OK" ]]; then
    osascript <<EOF
display dialog "Terminal needs Accessibility access.\n\nEnable it in:\nSystem Settings → Privacy & Security → Accessibility\n\nThen FULLY QUIT Terminal and re-run the script." buttons {"Open Settings"} default button 1 with icon caution
EOF
    open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  sleep 1
    osascript -e 'tell application "Terminal" to quit'

exit 1
  fi
  echo "Accessibility permission confirmed."
}

# ----------------------------------------
# Permissions
# ----------------------------------------
require_full_disk_access
require_accessibility

osascript -e 'tell application "Finder" to get name of front window' -e 'tell application "System Events" to get name of current user'




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

# -----------------------------
# Screenshot Directory Change
# -----------------------------

echo ""
echo "Configuring screenshot save location..."

# Create the folder for screenshots (if not already there)
mkdir -p "$HOME/Pictures/Screenshots"

# Set screenshot save location
defaults_write_if_needed com.apple.screencapture location -string "$HOME/Pictures/Screenshots"

echo "Screenshot save location set to ~/Pictures/Screenshots."

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

#List View
defaults write com.apple.finder FXPreferredViewStyle -string "Nlsv"

#Large Icons
defaults write com.apple.finder StandardViewSettings -dict-add "ListViewSettings" '<dict><key>iconSize</key><integer>32</integer></dict>'

#Calculate Folder Sizes
defaults write com.apple.finder FXCalculateAllSizes -bool true

#Refresh .DS_Store
echo "Refreshing .DS_Store Files — this may take a while..."
find "$HOME" \
  -path "$HOME/Library" -prune -o \
  -name ".DS_Store" -type f -delete 2>/dev/null

echo "Finder settings configured"

# -----------------------------
# TextEdit Preferences
# -----------------------------

echo "Configuring TextEdit..."

# Force plain text mode
defaults write com.apple.TextEdit RichText -bool false

# Encoding
defaults write com.apple.TextEdit PlainTextEncoding -int 4
defaults write com.apple.TextEdit PlainTextEncodingForWrite -int 4

# Global smart text rules
defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# Disable iCloud new document default
defaults write NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false

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
defaults write com.apple.dock persistent-apps '()'

# Disable "Show suggested and recent apps in Dock"
defaults_write_if_needed com.apple.dock show-recents -bool false

# Disable Mission Control & App Expose
defaults_write_if_needed com.apple.dock showMissionControlGestureEnabled -bool false
defaults_write_if_needed com.apple.dock showAppExposeGestureEnabled -bool false

echo "Dock settings applied."

# -----------------------------
# Change Spelling Settings
# -----------------------------

echo "Changing Spelling Settings..."

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
defaults_write_if_needed NSGlobalDomain NSNavPanelExpandedStateForSaveMode -bool true
defaults_write_if_needed NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 -bool true

# -----------------------------
# Apply settings
# -----------------------------
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
killall ControlCenter 2>/dev/null || true
killall SystemUIServer 2>/dev/null || true
killall TextEdit 2>/dev/null || true
killall cfprefsd 2>/dev/null || true

echo "All settings applied!"

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
# Tap custom Homebrew repo
# ----------------------------------------
echo ""
echo "Tapping MasterofDeath01/apps..."
brew_tap_if_missing "MasterofDeath01/apps"

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

sleep 3

osascript -e 'quit app "Shutter Encoder"' 2>/dev/null || true

mas install 310633997 #Whatsapp Messenger is also priviledged
# ----------------------------------------
# Install Rosetta (for Apple Silicon)
# ----------------------------------------
if [[ "$(uname -m)" == "arm64" ]]; then
  if ! /usr/bin/pgrep oahd >/dev/null 2>&1; then
    echo "Installing Rosetta..."
    softwareupdate --install-rosetta --agree-to-license
  else
    echo "Rosetta already installed."
  fi
fi

# ----------------------------------------
# Install custom apps & fonts
# ----------------------------------------
echo "Installing custom apps and fonts..."

brew_apps=(

#Custom Brew Casks

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
  
# Normal Brew Apps

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
  spicetify-cli
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

# Normal Fonts

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

for cask in "${brew_apps[@]}"; do
  echo "Installing $cask..."
  brew_install_if_missing "$cask"
done 

echo "Installing Mac App Store apps..."

mas_apps=(
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
  # Whatsapp has been moved to top because it requires admin
)

for app_id in "${mas_apps[@]}"; do
    echo "Installing MAS app $app_id..."
    mas_install_if_missing "$app_id"
  done

# ----------------------------------------
# Install Spicetify
# ----------------------------------------
open /Applications/Spotify.app 2>/dev/null || true

echo "Sign in to Spotify and wait 60s"...

sleep 180

spicetify config spotify_path "/Applications/Spotify.app/Contents/Resources"
spicetify update
spicetify apply
if [[ ! -d "$HOME/.spicetify/CustomApps/spicetify-marketplace" ]]; then
  curl -fsSL https://raw.githubusercontent.com/spicetify/marketplace/main/resources/install.sh | sh
fi
spicetify apply

  
# ----------------------------------------
# Download Personal Config Files
# ----------------------------------------

echo "Downloading personal config files..."

DOWNLOADS_DIR="$HOME/Downloads"

mkdir -p "$DOWNLOADS_DIR"

curl -L \
  -o "$DOWNLOADS_DIR/Raycast.rayconfig" \
  "https://raw.githubusercontent.com/MasterofDeath01/Mac-Setup/main/Raycast.rayconfig"

curl -L \
  -o "$DOWNLOADS_DIR/MasterofDeath's Editing Script.jsx" \
  "https://raw.githubusercontent.com/MasterofDeath01/Mac-Setup/main/MasterofDeath%27s%20Editing%20Script.jsx"

echo "Personal config files downloaded to Downloads."

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

  #Apps for Dock
  "Safari"
  "Modrinth App"
  "Discord"
  "WhatsApp"
  "ChatGPT"
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
