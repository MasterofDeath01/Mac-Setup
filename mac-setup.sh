#!/bin/bash
set -euo pipefail

echo ""

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

defaults_write_if_needed() {
  local domain="$1"
  local key="$2"
  shift 2

  local current
  current=$(defaults read "$domain" "$key" 2>/dev/null || true)

  if [[ "$current" == "$*" ]]; then
    echo "$domain $key already set."
  else
    defaults write "$domain" "$key" "$@"
    echo "Updated $domain $key"
  fi
}


# ----------------------------------------
# Permissions
# ----------------------------------------
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

require_full_disk_access
open / 2>/dev/null || true
osascript -e 'tell application "Finder" to get name of front window' -e 'tell application "System Events" to get name of current user'

# ----------------------------------------
# Enable Touch ID for sudo
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

echo ""
echo "======================================="
echo " CONFIGURE SETUP"
echo "======================================="
echo ""

ask_yes_no() {
  local prompt="$1"
  local reply

  read -rp "$prompt [y/n]: " reply

  [[ "$reply" =~ ^[Yy]$ ]]
}

if ask_yes_no "Configure macOS Settings?" "N"; then
  CONFIGURE_MACOS_SETTINGS=true
else
  CONFIGURE_MACOS_SETTINGS=false
fi

if ask_yes_no "Install Homebrew apps?" "Y"; then
  INSTALL_BREW_APPS=true
else
  INSTALL_BREW_APPS=false
fi

if ask_yes_no "Remove Microsoft Auto-Update?" "Y"; then
  REMOVE_MAU=true
else
  REMOVE_MAU=false
fi

if ask_yes_no "Launch apps at end of setup?" "Y"; then
  LAUNCH_APPS=true
else
  LAUNCH_APPS=false
fi

if ask_yes_no "Run Spotify setup?" "Y"; then
  RUN_SPOTIFY_SETUP=true
else
  RUN_SPOTIFY_SETUP=false
fi

if ask_yes_no "Refresh .DS_STORE files?" "N"; then
  REFRESH_DS_STORE=true
else
  REFRESH_DS_STORE=false
fi

if ask_yes_no "Launch apps at end of setup?" "Y"; then
  LAUNCH_APPS=true
else
  LAUNCH_APPS=false
fi

if [[ "$CONFIGURE_MACOS_SETTINGS" == true ]]; then

echo ""
echo "======================================="
echo " CONFIGURE MACOS SETTINGS"
echo "======================================="
echo ""

# ----------------------------------------
# Open Settings Panes
# ----------------------------------------

echo "Please configure the following in System Settings:"
echo "- Screenshot shortcuts"
echo "- Control Center"
echo "- Desktop & Dock"
echo "- Wallpaper"

open "x-apple.systempreferences:"

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

# Show all hidden files
defaults write com.apple.finder AppleShowAllFiles true

# Set Finder search to current folder by default
defaults_write_if_needed com.apple.finder FXDefaultSearchScope -string "SCcf"

# Set new Finder windows to open Downloads folder
defaults_write_if_needed com.apple.finder NewWindowTarget -string "PfLo"
defaults_write_if_needed com.apple.finder NewWindowTargetPath -string "file://${HOME}/Downloads/"

#Show Path and Status Bar
defaults_write_if_needed com.apple.finder ShowPathbar -bool true
defaults_write_if_needed com.apple.finder ShowStatusBar -bool true

#Calculate Folder Sizes
defaults_write_if_needed com.apple.finder FXCalculateAllSizes -bool true

echo "Finder settings configured"

# -----------------------------
# TextEdit Preferences
# -----------------------------

echo "Configuring TextEdit..."

# Force plain text mode
defaults_write_if_needed com.apple.TextEdit RichText -bool false

# Encoding
defaults_write_if_needed com.apple.TextEdit PlainTextEncoding -int 4
defaults_write_if_needed com.apple.TextEdit PlainTextEncodingForWrite -int 4

# Global smart text rules
defaults_write_if_needed NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false
defaults_write_if_needed NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false

# Disable iCloud new document default
defaults_write_if_needed NSGlobalDomain NSDocumentSaveNewDocumentsToCloud -bool false

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

else
echo "Skipping MacOS settings configuration..."
fi

if [[ "$INSTALL_BREW_APPS" == true ]]; then

echo ""
echo "======================================="
echo " INSTALL APPS"
echo "======================================="
echo ""

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

# ----------------------------------------
# Install Privileged Apps FIRST
# ----------------------------------------

brew tap masterofdeath01/apps
brew trust masterofdeath01/apps

privileged_apps=(
  auto-subs
  blackhole-2ch
  microsoft-teams
  mas
  powerpoint-2024
  excel-2024
  word-2024
  microsoft-serializer
  shutter-encoder
)

echo "Installing privileged apps..."
  for app in "${privileged_apps[@]}"; do
    echo "Installing $app..."
    brew_install_if_missing "$app"
  done
else
  echo "Skipping priviledged apps install..."
fi
sleep 2

osascript -e 'quit app "Shutter Encoder"' 2>/dev/null || true

if [[ "$INSTALL_MAS_APPS" == true ]]; then

mas_apps=(
  310633997  #Whatsapp Messenger
  6745342698 # Ublock Origin Lite
  6698876601 # Folder Preview
  1592917505 # Noir - Dark Mode for Safari
  510620098  # MediaInfo
  1448916662 # Step Two
  1355679052 # Dropover
)
  
  echo "Installing Mac App Store apps..."

  for app_id in "${mas_apps[@]}"; do
    echo "Installing MAS app $app_id..."
    mas_install_if_missing "$app_id"
  done

else
  echo "Skipping Mac App Store installs..."
fi

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

if [[ "$INSTALL_BREW_APPS" == true ]]; then

brew_apps=(

#Custom Brew Casks

  adobe-activation-tool
  topaz-video-enhance-ai
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
  stremio
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

  echo "Installing custom apps and fonts..."

  for cask in "${brew_apps[@]}"; do
    echo "Installing $cask..."
    brew_install_if_missing "$cask"
  done

else
  echo "Skipping Homebrew app installation..."
fi

if [[ "$REMOVE_MAU" == true ]]; then
echo ""
echo "======================================="
echo " REMOVE MICROSOFT AUTO UPDATE"
echo "======================================="
echo ""

sudo pkill -9 "Microsoft AutoUpdate"
sudo rm -rf "/Library/Application Support/Microsoft/MAU2.0"
sudo rm -f /Library/LaunchAgents/com.microsoft.update.agent.plist
sudo rm -f /Library/LaunchDaemons/com.microsoft.update.helper.plist
sudo rm -f /Library/PrivilegedHelperTools/com.microsoft.update.helper


else
  echo "Skipping removing MAU."
fi

if [[ "$RUN_SPOTIFY_SETUP" == true ]]; then

echo ""
echo "======================================="
echo " SPOTIFY SETUP"
echo "======================================="
echo ""

  if ! command -v spicetify >/dev/null 2>&1; then
   echo "Installing Spicetify CLI..."
    brew_install_if_missing spicetify-cli
  else
    echo "Spicetify already installed."
  fi

rm -rf ~/Library/Caches/com.spotify.client 2>/dev/null || true
brew uninstall legacy-spotify 2>/dev/null || true
  echo "Installing legacy Spotify..."

 brew_install_if_missing legacy-spotify

killall Spotify || true

chflags -R nouchg /Applications/Spotify.app || true
xattr -cr /Applications/Spotify.app || true
chmod -R 755 /Applications/Spotify.app || true

  echo "Launching Spotify for first login..."
  open -a "Spotify.app" || true
  read -rp "Log into Spotify fully, then press ENTER/RETURN..."

echo ""
echo "Waiting 60s before continuing..."
sleep 60

bash <(curl -sSL https://spotx-official.github.io/run.sh) --blockupdates

spicetify backup apply

  echo "Setting Spicetify Spotify path..."

  spicetify config spotify_path "/Applications/Spotify.app"

  echo "Installing Spotify Marketplace..."

  curl -fsSL https://raw.githubusercontent.com/spicetify/spicetify-marketplace/main/resources/install.sh | sh

  echo "Installing extensions..."

  mkdir -p "$HOME/.config/spicetify/Extensions"

  curl -L -o "$HOME/.config/spicetify/Extensions/adblock.js" \
    "https://raw.githubusercontent.com/MasterofDeath01/Mac-Setup/main/adblock.js"

  curl -L -o "$HOME/.config/spicetify/Extensions/loopyLoop.js" \
    "https://raw.githubusercontent.com/MasterofDeath01/Mac-Setup/main/loopyLoop.js"

  curl -L -o "$HOME/.config/spicetify/Extensions/spotifyBackup.js" \
    "https://raw.githubusercontent.com/MasterofDeath01/Mac-Setup/main/spotifyBackup.js"

  echo "Configuring Spicetify..."

  spicetify config extensions adblock.js
  spicetify config extensions loopyLoop.js
  spicetify config extensions spotifyBackup.js

  echo "Applying Spicetify..."
  
  spicetify apply

  echo "Restarting Spotify..."

  killall Spotify || true
  open -a "Spotify"

else
  echo "Skipping Spotify setup."
fi

# ----------------------------------------
# Download Personal Config Files
# ----------------------------------------

DOWNLOADS_DIR="$HOME/Downloads"
echo "Downloading personal config files..."

mkdir -p "$DOWNLOADS_DIR"

curl -L \
  -o "$DOWNLOADS_DIR/Raycast.rayconfig" \
  "https://raw.githubusercontent.com/MasterofDeath01/Mac-Setup/main/Raycast.rayconfig"

SCRIPT_NAME="MasterofDeath's Editing Script.jsx"

curl -L \
  -o "$DOWNLOADS_DIR/$SCRIPT_NAME" \
  "https://raw.githubusercontent.com/MasterofDeath01/Mac-Setup/main/MasterofDeath%27s%20Editing%20Script.jsx"

echo "Personal config files downloaded to Downloads."

# ----------------------------------------
# Xattr Apps
# ----------------------------------------

sudo xattr -cr /Applications/Mos.app
sudo xattr -cr /Applications/'Topaz Video.app'
sudo xattr -cr /Applications/'Adobe Downloader.app'
sudo xattr -cr /Applications/Adobe\ Activation\ Tool.app

# ----------------------------------------
# Refresh DS_STORE
# ----------------------------------------

if [[ "$REFRESH_DS_STORE" == true ]]; then
  echo ""
  echo "Refreshing .DS_Store Files — this may take a while..."

  find "$HOME" \
    -path "$HOME/Library" -prune -o \
    -name ".DS_Store" -type f -delete 2>/dev/null

  echo ".DS_Store refresh complete."

else
  echo "Skipping .DS_Store refresh."
fi

# ----------------------------------------
# Launch Installed Apps
# ----------------------------------------

if [[ "$LAUNCH_APPS" == true ]]; then

echo ""
echo "======================================="
echo " LAUNCHING APPS"
echo "======================================="
echo ""

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
  "Surfshark"

  #Apps for Dock
  "Safari"
  "Modrinth App"
  "Discord"
  "WhatsApp"
  "ChatGPT"
)

  echo "Opening selected apps..."

  for app in "${apps_to_open[@]}"; do
    echo "Opening $app..."
    open -a "$app" 2>/dev/null || echo "$app not installed or failed to open"
  done

else
  echo "Skipping app launch section."
fi

brew cleanup

echo "======================================="
echo " Setup complete!"
echo "======================================="

osascript -e 'tell app "System Events" to display dialog "Setup Complete!"'

read -n 1 -s -r -p "Press any key to close…"
