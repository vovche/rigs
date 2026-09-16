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

echo "=== Build & Installation Complete! ==="
echo "Binary: ${INSTALL_PREFIX}/bin/rigs"
