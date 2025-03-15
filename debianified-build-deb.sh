#!/bin/bash
set -e

# Configuration variables
PACKAGE_NAME="claude-desktop"
ARCHITECTURE="amd64"
MAINTAINER="Your Name <your.email@example.com>"
DESCRIPTION="Claude Desktop for Linux"
SECTION="utils"
PRIORITY="optional"
HOMEPAGE="https://www.anthropic.com"

# Update this URL when a new version of Claude Desktop is released
CLAUDE_DOWNLOAD_URL="https://storage.googleapis.com/osprey-downloads-c02f6a0d-347c-492b-a752-3e0651722e97/nest-win-x64/Claude-Setup-x64.exe"

# Check for Debian-based system
if [ ! -f "/etc/debian_version" ]; then
    echo "❌ This script requires a Debian-based Linux distribution"
    exit 1
fi

# Check for root/sudo
if [ "$EUID" -ne 0 ]; then
    echo "Please run with sudo to install build dependencies"
    exit 1
fi

# Print system information
echo "System Information:"
echo "Distribution: $(cat /etc/os-release | grep "PRETTY_NAME" | cut -d'"' -f2)"
echo "Debian version: $(cat /etc/debian_version)"

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo "❌ $1 not found"
        return 1
    else
        echo "✓ $1 found"
        return 0
    fi
}

# Check and install dependencies
echo "Checking build dependencies..."
BUILD_DEPS="p7zip-full wget icoutils imagemagick nodejs npm dpkg-dev debhelper lintian"

for dep in $BUILD_DEPS; do
    if ! dpkg -l | grep -q "ii  $dep"; then
        echo "Installing $dep..."
        apt-get update -qq
        apt-get install -y $dep
    else
        echo "✓ $dep already installed"
    fi
done

# Install electron globally via npm if not present
if ! check_command "electron"; then
    echo "Installing electron via npm..."
    npm install -g electron
    if ! check_command "electron"; then
        echo "Failed to install electron. Please install it manually:"
        echo "sudo npm install -g electron"
        exit 1
    fi
    echo "Electron installed successfully"
fi

# Install asar if needed
if ! npm list -g asar > /dev/null 2>&1; then
    echo "Installing asar package globally..."
    npm install -g asar
fi

# Create working directories
WORK_DIR="$(pwd)/build-$PACKAGE_NAME"
DEB_ROOT="$WORK_DIR/$PACKAGE_NAME"
INSTALL_DIR="$DEB_ROOT/usr"
DEBIAN_DIR="$DEB_ROOT/DEBIAN"

# Clean previous build
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
mkdir -p "$DEBIAN_DIR"
mkdir -p "$INSTALL_DIR/lib/$PACKAGE_NAME"
mkdir -p "$INSTALL_DIR/share/applications"
mkdir -p "$INSTALL_DIR/share/pixmaps"
mkdir -p "$INSTALL_DIR/bin"
mkdir -p "$INSTALL_DIR/share/doc/$PACKAGE_NAME"

# Download Claude Windows installer
echo "📥 Downloading Claude Desktop installer..."
CLAUDE_EXE="$WORK_DIR/Claude-Setup-x64.exe"
if ! wget -O "$CLAUDE_EXE" "$CLAUDE_DOWNLOAD_URL"; then
    echo "❌ Failed to download Claude Desktop installer"
    exit 1
fi
echo "✓ Download complete"

# Extract resources
echo "📦 Extracting resources..."
cd "$WORK_DIR"
if ! 7z x -y "$CLAUDE_EXE"; then
    echo "❌ Failed to extract installer"
    exit 1
fi

# Try to extract the version from the NuPkg file
NUPKG_FILE=$(find . -name "AnthropicClaude-*-full.nupkg" | head -1)

if [ -z "$NUPKG_FILE" ]; then
    echo "❌ Could not find AnthropicClaude-*-full.nupkg file"
    exit 1
fi

# Extract version from the nupkg filename
VERSION=$(echo "$NUPKG_FILE" | grep -oP "AnthropicClaude-\K[0-9]+\.[0-9]+\.[0-9]+" || echo "0.8.0")
echo "Detected version: $VERSION"

if ! 7z x -y "$NUPKG_FILE"; then
    echo "❌ Failed to extract nupkg"
    exit 1
fi
echo "✓ Resources extracted"

# Extract and convert icons
echo "🎨 Processing icons..."
if ! wrestool -x -t 14 "lib/net45/claude.exe" -o claude.ico; then
    echo "❌ Failed to extract icons from exe"
    exit 1
fi

if ! icotool -x claude.ico; then
    echo "❌ Failed to convert icons"
    exit 1
fi
echo "✓ Icons processed"

# Map icon sizes to their corresponding extracted files
declare -A icon_files=(
    ["16"]="claude_13_16x16x32.png"
    ["24"]="claude_11_24x24x32.png"
    ["32"]="claude_10_32x32x32.png"
    ["48"]="claude_8_48x48x32.png"
    ["64"]="claude_7_64x64x32.png"
    ["256"]="claude_6_256x256x32.png"
)

# Install icons according to Debian standards
for size in 16 24 32 48 64 256; do
    icon_dir="$INSTALL_DIR/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    if [ -f "${icon_files[$size]}" ]; then
        echo "Installing ${size}x${size} icon..."
        install -Dm 644 "${icon_files[$size]}" "$icon_dir/$PACKAGE_NAME.png"
    else
        echo "Warning: Missing ${size}x${size} icon"
    fi
done

# Also install the main icon to pixmaps
if [ -f "${icon_files[64]}" ]; then
    install -Dm 644 "${icon_files[64]}" "$INSTALL_DIR/share/pixmaps/$PACKAGE_NAME.png"
fi

# Process app.asar
mkdir -p electron-app
cp "lib/net45/resources/app.asar" electron-app/
cp -r "lib/net45/resources/app.asar.unpacked" electron-app/ 2>/dev/null || true

cd electron-app
npx asar extract app.asar app.asar.contents

# Replace native module with stub implementation
echo "Creating stub native module..."
mkdir -p app.asar.contents/node_modules/claude-native
cat > app.asar.contents/node_modules/claude-native/index.js << EOF
// Stub implementation of claude-native using KeyboardKey enum values
const KeyboardKey = {
  Backspace: 43,
  Tab: 280,
  Enter: 261,
  Shift: 272,
  Control: 61,
  Alt: 40,
  CapsLock: 56,
  Escape: 85,
  Space: 276,
  PageUp: 251,
  PageDown: 250,
  End: 83,
  Home: 154,
  LeftArrow: 175,
  UpArrow: 282,
  RightArrow: 262,
  DownArrow: 81,
  Delete: 79,
  Meta: 187
};

Object.freeze(KeyboardKey);

module.exports = {
  getWindowsVersion: () => "10.0.0",
  setWindowEffect: () => {},
  removeWindowEffect: () => {},
  getIsMaximized: () => false,
  flashFrame: () => {},
  clearFlashFrame: () => {},
  showNotification: () => {},
  setProgressBar: () => {},
  clearProgressBar: () => {},
  setOverlayIcon: () => {},
  clearOverlayIcon: () => {},
  KeyboardKey
};
EOF

# Copy Tray icons
mkdir -p app.asar.contents/resources
mkdir -p app.asar.contents/resources/i18n

# Copy resources if they exist
cp -f ../lib/net45/resources/Tray* app.asar.contents/resources/ 2>/dev/null || true
cp -f ../lib/net45/resources/*-*.json app.asar.contents/resources/i18n/ 2>/dev/null || true

# Repackage app.asar
npx asar pack app.asar.contents app.asar

# Create native module with keyboard constants
mkdir -p "$INSTALL_DIR/lib/$PACKAGE_NAME/app.asar.unpacked/node_modules/claude-native"
cat > "$INSTALL_DIR/lib/$PACKAGE_NAME/app.asar.unpacked/node_modules/claude-native/index.js" << EOF
// Stub implementation of claude-native using KeyboardKey enum values
const KeyboardKey = {
  Backspace: 43,
  Tab: 280,
  Enter: 261,
  Shift: 272,
  Control: 61,
  Alt: 40,
  CapsLock: 56,
  Escape: 85,
  Space: 276,
  PageUp: 251,
  PageDown: 250,
  End: 83,
  Home: 154,
  LeftArrow: 175,
  UpArrow: 282,
  RightArrow: 262,
  DownArrow: 81,
  Delete: 79,
  Meta: 187
};

Object.freeze(KeyboardKey);

module.exports = {
  getWindowsVersion: () => "10.0.0",
  setWindowEffect: () => {},
  removeWindowEffect: () => {},
  getIsMaximized: () => false,
  flashFrame: () => {},
  clearFlashFrame: () => {},
  showNotification: () => {},
  setProgressBar: () => {},
  clearProgressBar: () => {},
  setOverlayIcon: () => {},
  clearOverlayIcon: () => {},
  KeyboardKey
};
EOF

# Copy app files
cp app.asar "$INSTALL_DIR/lib/$PACKAGE_NAME/"
mkdir -p "$INSTALL_DIR/lib/$PACKAGE_NAME/app.asar.unpacked"
cp -r app.asar.unpacked/* "$INSTALL_DIR/lib/$PACKAGE_NAME/app.asar.unpacked/" 2>/dev/null || true
cd "$WORK_DIR"

# Create desktop entry compliant with FreeDesktop standards
cat > "$INSTALL_DIR/share/applications/$PACKAGE_NAME.desktop" << EOF
[Desktop Entry]
Name=Claude
GenericName=AI Assistant
Comment=Chat with Claude, an AI assistant from Anthropic
Exec=$PACKAGE_NAME %u
Icon=$PACKAGE_NAME
Type=Application
Terminal=false
Categories=Office;Utility;Productivity;
MimeType=x-scheme-handler/claude;
StartupWMClass=Claude
Keywords=AI;Chat;Assistant;Claude;Anthropic;
EOF

# Create launcher script with proper shebang
cat > "$INSTALL_DIR/bin/$PACKAGE_NAME" << EOF
#!/bin/bash
exec electron /usr/lib/$PACKAGE_NAME/app.asar "\$@"
EOF
chmod +x "$INSTALL_DIR/bin/$PACKAGE_NAME"

# Create copyright file
cat > "$INSTALL_DIR/share/doc/$PACKAGE_NAME/copyright" << EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: Claude Desktop
Upstream-Contact: Anthropic <support@anthropic.com>
Source: https://www.anthropic.com

Files: *
Copyright: $(date +%Y) Anthropic
License: Proprietary
 This software is a proprietary product of Anthropic.
 All rights reserved.
EOF

# Create changelog file
cat > "$INSTALL_DIR/share/doc/$PACKAGE_NAME/changelog.Debian" << EOF
$PACKAGE_NAME ($VERSION-1) unstable; urgency=medium

  * Unofficial package of Claude Desktop for Linux

 -- $MAINTAINER  $(date -R)
EOF
gzip -9 -n "$INSTALL_DIR/share/doc/$PACKAGE_NAME/changelog.Debian"

# Create control file
cat > "$DEBIAN_DIR/control" << EOF
Package: $PACKAGE_NAME
Version: $VERSION-1
Section: $SECTION
Priority: $PRIORITY
Architecture: $ARCHITECTURE
Maintainer: $MAINTAINER
Depends: nodejs (>= 12.0.0), npm, libasound2, libatk1.0-0, libatk-bridge2.0-0, libcairo2, libcups2, libexpat1, libgbm1, libglib2.0-0, libnspr4, libnss3, libpango-1.0-0, libx11-6, libxcomposite1, libxdamage1, libxext6, libxfixes3, libxkbcommon0, libxrandr2
Homepage: $HOMEPAGE
Description: $DESCRIPTION
 Claude is an AI assistant from Anthropic.
 This package provides the desktop interface for Claude.
 .
 Unofficial packaging for Debian-based Linux distributions.
EOF

# Create postinst script
cat > "$DEBIAN_DIR/postinst" << EOF
#!/bin/sh
set -e

# Add mime type handler
if [ "\$1" = "configure" ] || [ "\$1" = "abort-upgrade" ]; then
    update-desktop-database -q || true
fi

#DEBHELPER#
exit 0
EOF
chmod 755 "$DEBIAN_DIR/postinst"

# Create prerm script
cat > "$DEBIAN_DIR/prerm" << EOF
#!/bin/sh
set -e

#DEBHELPER#
exit 0
EOF
chmod 755 "$DEBIAN_DIR/prerm"

# Create md5sums file
cd "$DEB_ROOT"
find usr -type f -exec md5sum {} \; > "$DEBIAN_DIR/md5sums"
cd "$WORK_DIR"

# Set correct file permissions
find "$DEB_ROOT" -type d -exec chmod 755 {} \;
find "$INSTALL_DIR/share/doc" -type f -exec chmod 644 {} \;

# Build .deb package
echo "📦 Building .deb package..."
DEB_FILE="$WORK_DIR/${PACKAGE_NAME}_${VERSION}-1_${ARCHITECTURE}.deb"
if ! dpkg-deb --build --root-owner-group "$DEB_ROOT" "$DEB_FILE"; then
    echo "❌ Failed to build .deb package"
    exit 1
fi

# Verify package with lintian
# Verify package with lintian
echo "🔍 Verifying package with lintian..."
lintian --tag-display-limit 0 "$DEB_FILE" || true

if [ -f "$DEB_FILE" ]; then
    echo "✓ Package built successfully at: $DEB_FILE"
    echo "🎉 Done! You can now install the package with: sudo dpkg -i $DEB_FILE"
    
    # Instructions for setting up a repository
    echo ""
    echo "===== REPOSITORY SETUP INSTRUCTIONS ====="
    echo "To set up a repository for distribution, follow these steps:"
    echo ""
    echo "1. Create a repository structure:"
    echo "   mkdir -p ~/apt-repo/pool/main/$PACKAGE_NAME"
    echo "   mkdir -p ~/apt-repo/dists/stable/{main,contrib,non-free}/{binary-amd64,binary-i386,source}"
    echo ""
    echo "2. Copy the built .deb package to the pool directory:"
    echo "   cp $DEB_FILE ~/apt-repo/pool/main/$PACKAGE_NAME/"
    echo ""
    echo "3. Generate the package indexes:"
    echo "   cd ~/apt-repo"
    echo "   dpkg-scanpackages --multiversion pool/ > dists/stable/main/binary-amd64/Packages"
    echo "   gzip -k -f dists/stable/main/binary-amd64/Packages"
    echo ""
    echo "4. Create a Release file:"
    echo "   cd ~/apt-repo/dists/stable"
    echo "   echo \"Origin: Your Repository Name\" > Release"
    echo "   echo \"Label: Your Repository Label\" >> Release"
    echo "   echo \"Suite: stable\" >> Release"
    echo "   echo \"Codename: stable\" >> Release"
    echo "   echo \"Version: 1.0\" >> Release"
    echo "   echo \"Architectures: amd64\" >> Release"
    echo "   echo \"Components: main contrib non-free\" >> Release"
    echo "   echo \"Description: Your Repository Description\" >> Release"
    echo "   echo \"Date: $(date -R)\" >> Release"
    echo ""
    echo "   # Add md5sum"
    echo "   echo \"MD5Sum:\" >> Release"
    echo "   cd ~/apt-repo"
    echo "   find dists/stable -type f -not -name \"Release\" -not -path \"*.git*\" -exec md5sum {} \\; | sed \"s/  / /g\" | sed \"s,^,  ,\" | sed \"s,dists/stable/,./,\" >> dists/stable/Release"
    echo ""
    echo "5. If you want to sign the Release file (recommended):"
    echo "   cd ~/apt-repo/dists/stable"
    echo "   gpg --default-key \"your-email@example.com\" -abs -o Release.gpg Release"
    echo "   gpg --default-key \"your-email@example.com\" --clearsign -o InRelease Release"
    echo ""
    echo "6. Serve the repository:"
    echo "   You can serve the repository using a web server like Apache or Nginx."
    echo "   The repository should be accessible at http://your-server/apt-repo/"
    echo ""
    echo "7. Users can add the repository with:"
    echo "   sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys YOUR_GPG_KEY_ID"
    echo "   echo \"deb http://your-server/apt-repo/ stable main\" | sudo tee /etc/apt/sources.list.d/your-repo.list"
    echo "   sudo apt update"
    echo "   sudo apt install $PACKAGE_NAME"
    echo ""
    echo "Alternatively, you can use an existing PPA or repository service."
    echo "===== END REPOSITORY SETUP INSTRUCTIONS ====="
else
    echo "❌ Package file not found at expected location: $DEB_FILE"
    exit 1
fi