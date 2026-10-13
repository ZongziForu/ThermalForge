#!/bin/bash
# Install the customized GUI + daemon together, and retire the old duplicate GUI.
# Run as the normal user; sudo prompts in the terminal, never through the app.
set -euo pipefail
cd "$(dirname "$0")"
if [ "$(id -u)" -eq 0 ]; then
    echo "Run ./install-custom.sh as your normal user, not sudo."
    exit 1
fi

echo "Building customized ThermalForge..."
swift build -c release --quiet
echo "The administrator password is needed to replace the system daemon."
sudo -v

BACKUP_DIR="$PWD/.local-install/backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
chmod 700 "$PWD/.local-install" "$PWD/.local-install/backups" "$BACKUP_DIR"
LEGACY_USER_APP="$HOME/Applications/ThermalForge.app"
if [ -e "$LEGACY_USER_APP" ]; then
    /usr/bin/ditto -c -k --keepParent "$LEGACY_USER_APP" "$BACKUP_DIR/legacy-user-app.zip"
fi
if [ -d /Applications/ThermalForge.app ]; then
    /usr/bin/ditto -c -k --keepParent /Applications/ThermalForge.app "$BACKUP_DIR/previous-system-app.zip"
elif [ -f /Applications/ThermalForge.app ]; then
    cp /Applications/ThermalForge.app "$BACKUP_DIR/legacy-flat-app.bin"
fi
if [ -f /usr/local/bin/thermalforge ]; then
    cp /usr/local/bin/thermalforge "$BACKUP_DIR/previous-cli.bin"
fi
if [ -f /Library/LaunchDaemons/com.thermalforge.daemon.plist ]; then
    cp /Library/LaunchDaemons/com.thermalforge.daemon.plist "$BACKUP_DIR/previous-daemon.plist"
fi
if [ -d "$HOME/Library/Application Support/ThermalForge" ]; then
    /usr/bin/ditto "$HOME/Library/Application Support/ThermalForge" "$BACKUP_DIR/user-data"
fi
echo "Rollback archive: $BACKUP_DIR"

pkill -x TouchBarPreview 2>/dev/null || true
./setup.sh
/usr/bin/codesign --verify --deep --strict /Applications/ThermalForge.app
EXPECTED_VERSION=$(.build/release/thermalforge --version)
ACTUAL_VERSION=$(/usr/local/bin/thermalforge --version)
if [ "$EXPECTED_VERSION" != "$ACTUAL_VERSION" ]; then
    echo "CLI version mismatch; the old user app has not been removed."
    exit 1
fi
# The status client speaks the new protocol. A successful response verifies that
# launchd is serving the new daemon, rather than a surviving old process.
/usr/local/bin/thermalforge status > "$BACKUP_DIR/post-install-status.txt"

if [ -e "$LEGACY_USER_APP" ] && [ -s "$BACKUP_DIR/legacy-user-app.zip" ]; then
    # A fixed, exact path; the full bundle was archived before installation.
    rm -rf -- "$LEGACY_USER_APP"
fi
pkill -x ThermalForgeApp 2>/dev/null || true
defaults write com.thermalforge.app selectedProfile -string summer-smooth
defaults write com.thermalforge.app touchBarEnabled -bool true
/usr/bin/mdimport /Applications/ThermalForge.app 2>/dev/null || true
open /Applications/ThermalForge.app
echo "Installed $ACTUAL_VERSION. Old duplicate retired; profiles and calibration preserved."
echo "Check Summer Smooth and the Touch Bar fan/temperature button."
