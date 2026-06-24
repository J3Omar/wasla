#!/bin/bash

set -e

echo "🚀 Building Flutter Linux Application in Release mode..."
flutter build linux --release

STAGE_DIR="/tmp/wasla_debian_package"
rm -rf "$STAGE_DIR"

echo "📂 Creating Debian directory structure in /tmp..."
mkdir -p "$STAGE_DIR/DEBIAN"
mkdir -p "$STAGE_DIR/usr/bin"
mkdir -p "$STAGE_DIR/usr/lib/wasla"
mkdir -p "$STAGE_DIR/usr/share/applications"
mkdir -p "$STAGE_DIR/usr/share/pixmaps"

chmod 755 "$STAGE_DIR/DEBIAN"

echo "📦 Copying build files to system structure..."
cp -r build/linux/x64/release/bundle/* "$STAGE_DIR/usr/lib/wasla/"

cat << 'EOF' > "$STAGE_DIR/usr/bin/wasla"
#!/bin/bash
/usr/lib/wasla/wasla "$@"
EOF
chmod +x "$STAGE_DIR/usr/bin/wasla"

if [ -f "assets/images/Wasla-logo.png" ]; then
    cp assets/images/Wasla-logo.png "$STAGE_DIR/usr/share/pixmaps/wasla.png"
fi

echo "🖥️ Creating Shortcut Menu Icon..."
cat << 'EOF' > "$STAGE_DIR/usr/share/applications/wasla.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Wasla
Comment=Local P2P File Transfer Application
Exec=wasla
Icon=wasla
Terminal=false
Categories=Network;FileTransfer;
EOF

echo "📝 Generating Clean DEBIAN/control file..."
cat << 'EOF' > "$STAGE_DIR/DEBIAN/control"
Package: wasla
Version: 1.0.0
Architecture: amd64
Maintainer: Omar Hamada <omarworknow@gmail.com>
Depends: libc6, libgtk-3-0, libglib2.0-0, libsecret-1-0
Section: net
Priority: standard
Description: Local P2P File Transfer Application.
 Wasla is a decentralized, peer-to-peer file transfer and communication
 application built with Flutter and WebRTC for high-speed local network transfers.
EOF

chmod 644 "$STAGE_DIR/DEBIAN/control"

echo "📦 Packaging everything into .deb file using dpkg-deb..."

mkdir -p build/dist

dpkg-deb --build "$STAGE_DIR" "/tmp/wasla_1.0.0_amd64.deb"

cp "/tmp/wasla_1.0.0_amd64.deb" build/dist/wasla_1.0.0_amd64.deb

rm "/tmp/wasla_1.0.0_amd64.deb"
rm -rf "$STAGE_DIR"

echo "✅ Success! Debian package created at: build/dist/wasla_1.0.0_amd64.deb"#!/bin/bash

echo "🚀 Building Flutter Linux Application in Release mode..."
flutter build linux --release

OUTPUT_DIR="build/debian_package"
rm -rf "$OUTPUT_DIR"

echo "📂 Creating Debian directory structure..."
mkdir -p "$OUTPUT_DIR/DEBIAN"
mkdir -p "$OUTPUT_DIR/usr/bin"
mkdir -p "$OUTPUT_DIR/usr/lib/wasla"
mkdir -p "$OUTPUT_DIR/usr/share/applications"
mkdir -p "$OUTPUT_DIR/usr/share/pixmaps"

echo "📦 Copying build files to system structure..."
cp -r build/linux/x64/release/bundle/* "$OUTPUT_DIR/usr/lib/wasla/"

cat << 'EOF' > "$OUTPUT_DIR/usr/bin/wasla"
#!/bin/bash
/usr/lib/wasla/wasla "$@"
EOF
chmod +x "$OUTPUT_DIR/usr/bin/wasla"

if [ -f "assets/images/Wasla-logo.png" ]; then
    cp assets/images/Wasla-logo.png "$OUTPUT_DIR/usr/share/pixmaps/wasla.png"
fi

echo "🖥️ Creating Shortcut Menu Icon..."
cat << 'EOF' > "$OUTPUT_DIR/usr/share/applications/wasla.desktop"
[Desktop Entry]
Version=1.0
Type=Application
Name=Wasla
Comment=Local P2P File Transfer Application
Exec=wasla
Icon=wasla
Terminal=false
Categories=Network;FileTransfer;
EOF

echo "📝 Generating Clean DEBIAN/control file..."
cat << 'EOF' > "$OUTPUT_DIR/DEBIAN/control"
Package: wasla
Version: 1.0.0
Architecture: amd64
Maintainer: Omar Hamada <omarworknow@gmail.com>
Depends: libc6, libgtk-3-0, libglib2.0-0, libsecret-1-0
Section: net
Priority: standard
Description: Local P2P File Transfer Application.
 Wasla is a decentralized, peer-to-peer file transfer and communication
 application built with Flutter and WebRTC for high-speed local network transfers.
EOF

echo "📦 Packaging everything into .deb file using dpkg-deb..."
mkdir -p build/dist
dpkg-deb --build "$OUTPUT_DIR" "build/dist/wasla_1.0.0_amd64.deb"

echo "✅ Success! Debian package created at: build/dist/wasla_1.0.0_amd64.deb"