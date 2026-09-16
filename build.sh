#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/build"
INSTALL_PREFIX="${HOME}/.local"

echo "=== Building Rigs (Native Vala + Libadwaita) ==="

# Check if local valac and meson exist
if command -v valac >/dev/null 2>&1 && command -v meson >/dev/null 2>&1; then
    echo "Using local toolchain..."
    meson setup "${BUILD_DIR}" "${SCRIPT_DIR}" --prefix="${INSTALL_PREFIX}"
    meson compile -C "${BUILD_DIR}"
    meson test -C "${BUILD_DIR}" --verbose
else
    echo "Using rootless container toolchain (rigs-builder)..."
    if ! podman image exists rigs-builder; then
        echo "Building rigs-builder image..."
        podman build -t rigs-builder -f "${SCRIPT_DIR}/Containerfile" "${SCRIPT_DIR}"
    fi

    # Run build and tests inside container with mounted workspace
    podman run --rm \
        --userns=keep-id \
        -v "${SCRIPT_DIR}:/workspace:Z" \
        -w /workspace \
        rigs-builder \
        bash -c "
            set -e
            if [ ! -d build ]; then
                meson setup build --prefix=${INSTALL_PREFIX}
            fi
            meson compile -C build
            meson test -C build --verbose
        "
fi

echo "=== Installing executable to ${INSTALL_PREFIX}/bin/rigs ==="
mkdir -p "${INSTALL_PREFIX}/bin"
cp "${BUILD_DIR}/src/rigs" "${INSTALL_PREFIX}/bin/rigs"
chmod +x "${INSTALL_PREFIX}/bin/rigs"

echo "=== Installing desktop file and icons ==="
mkdir -p "${INSTALL_PREFIX}/share/applications"
cp "${SCRIPT_DIR}/data/io.github.vovche.Rigs.desktop" "${INSTALL_PREFIX}/share/applications/io.github.vovche.Rigs.desktop"

mkdir -p "${INSTALL_PREFIX}/share/icons/hicolor/scalable/apps"
cp "${SCRIPT_DIR}/data/icons/hicolor/scalable/apps/io.github.vovche.Rigs.svg" "${INSTALL_PREFIX}/share/icons/hicolor/scalable/apps/io.github.vovche.Rigs.svg"

mkdir -p "${INSTALL_PREFIX}/share/icons/hicolor/symbolic/apps"
cp "${SCRIPT_DIR}/data/icons/hicolor/symbolic/apps/io.github.vovche.Rigs-symbolic.svg" "${INSTALL_PREFIX}/share/icons/hicolor/symbolic/apps/io.github.vovche.Rigs-symbolic.svg"

for size in 48x48 64x64 128x128 256x256 512x512; do
    mkdir -p "${INSTALL_PREFIX}/share/icons/hicolor/${size}/apps"
    cp "${SCRIPT_DIR}/data/icons/hicolor/${size}/apps/io.github.vovche.Rigs.png" "${INSTALL_PREFIX}/share/icons/hicolor/${size}/apps/io.github.vovche.Rigs.png"
done

if [ ! -f "${INSTALL_PREFIX}/share/icons/hicolor/index.theme" ] && [ -f /usr/share/icons/hicolor/index.theme ]; then
    cp /usr/share/icons/hicolor/index.theme "${INSTALL_PREFIX}/share/icons/hicolor/index.theme"
fi
gtk-update-icon-cache -q -f "${INSTALL_PREFIX}/share/icons/hicolor" 2>/dev/null || true
update-desktop-database "${INSTALL_PREFIX}/share/applications" 2>/dev/null || true

echo "=== Installing GNOME Shell search provider and D-Bus service ==="
mkdir -p "${INSTALL_PREFIX}/share/gnome-shell/search-providers"
cp "${SCRIPT_DIR}/data/io.github.vovche.Rigs.search-provider.ini" "${INSTALL_PREFIX}/share/gnome-shell/search-providers/io.github.vovche.Rigs.search-provider.ini"

mkdir -p "${INSTALL_PREFIX}/share/dbus-1/services"
sed "s|@bindir@|${INSTALL_PREFIX}/bin|g" "${SCRIPT_DIR}/data/io.github.vovche.Rigs.service.in" > "${INSTALL_PREFIX}/share/dbus-1/services/io.github.vovche.Rigs.service"

echo "=== Installing translations to ${INSTALL_PREFIX}/share/locale ==="
for mo in "${BUILD_DIR}"/po/*/LC_MESSAGES/rigs.mo; do
    lang="$(basename "$(dirname "$(dirname "${mo}")")")"
    dest_dir="${INSTALL_PREFIX}/share/locale/${lang}/LC_MESSAGES"
    mkdir -p "${dest_dir}"
    cp "${mo}" "${dest_dir}/rigs.mo"
done

echo "=== Build & Installation Complete! ==="
echo "Binary: ${INSTALL_PREFIX}/bin/rigs"
