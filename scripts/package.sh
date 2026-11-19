#!/usr/bin/env bash
# package.sh — build .deb, .rpm and Arch packages into dist/.
#
#   scripts/package.sh deb|rpm|arch|all     build in rootless podman containers (any distro host)
#   scripts/package.sh --inside deb|rpm|arch run in the matching distro already (CI jobs use this)
#
# Packages are built from the COMMITTED tree (git archive of HEAD), exactly like a distro would
# build a release tarball, and every build runs the unit tests and the repository lint.
# Version: meson.build. HEAD not at tag v<version> → snapshot version (deb 0.9.0+git12.2a16a7b,
# rpm 0.9.0-1.git12.2a16a7b, arch 0.9.0.r12.g2a16a7b), so a later release upgrades cleanly.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="${DIST:-$ROOT/dist}"
DEB_IMAGE="${DEB_IMAGE:-docker.io/library/ubuntu:24.04}"   # oldest supported: works on 24.04+ and Debian 13
RPM_IMAGE="${RPM_IMAGE:-registry.fedoraproject.org/fedora:42}"
ARCH_IMAGE="${ARCH_IMAGE:-docker.io/library/archlinux:latest}"

die() { echo "package.sh: $*" >&2; exit 1; }

VERSION="${VERSION:-$(sed -n "s/^ *version: '\([^']*\)',/\1/p" "$ROOT/meson.build" | head -1)}"
[[ -n "$VERSION" ]] || die "cannot read the version from meson.build"
TARBALL="$DIST/rigs-$VERSION.tar.gz"

# SNAP_N / SNAP_SHA come from the host (containers have no git history); empty = release build.
snapshot_info() {
    if [[ -n "${SNAP_SHA+x}" ]]; then return; fi
    SNAP_N=""; SNAP_SHA=""
    if [[ "$(git -C "$ROOT" describe --exact-match --tags HEAD 2>/dev/null)" != "v$VERSION" ]]; then
        SNAP_N="$(git -C "$ROOT" rev-list --count "v$VERSION..HEAD" 2>/dev/null || git -C "$ROOT" rev-list --count HEAD)"
        SNAP_SHA="$(git -C "$ROOT" rev-parse --short=7 HEAD)"
    fi
}

make_tarball() {
    mkdir -p "$DIST"
    if [[ -n "$(git -C "$ROOT" status --porcelain --untracked-files=no)" ]]; then
        echo "package.sh: note — uncommitted changes are NOT packaged (building HEAD)." >&2
    fi
    git -C "$ROOT" archive --format=tar.gz --prefix="rigs-$VERSION/" -o "$TARBALL" HEAD
    echo "source: $TARBALL"
}

unpack() { # → prints the unpacked source directory
    local work; work="$(mktemp -d)"
    tar -xzf "$TARBALL" -C "$work"
    echo "$work/rigs-$VERSION"
}

inside_deb() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --no-install-recommends build-essential devscripts equivs >/dev/null
    local src; src="$(unpack)"
    cd "$src"
    if [[ -n "$SNAP_SHA" ]]; then sed -i "1s/(.*)/($VERSION+git$SNAP_N.$SNAP_SHA)/" debian/changelog; fi
    mk-build-deps -i -r -t "apt-get -y -qq --no-install-recommends" debian/control >/dev/null
    dpkg-buildpackage -us -uc -b
    cp ../rigs_*.deb "$DIST/"
}

inside_rpm() {
    dnf -y -q install rpm-build dnf5-plugins >/dev/null
    local src; src="$(unpack)"
    dnf -y -q builddep "$src/packaging/rpm/rigs.spec" >/dev/null
    local args=(--define "_sourcedir $DIST" --define "_rpmdir $DIST")
    if [[ -n "$SNAP_SHA" ]]; then args+=(--define "snapshot .git$SNAP_N.$SNAP_SHA"); fi
    rpmbuild -bb "${args[@]}" "$src/packaging/rpm/rigs.spec"
    find "$DIST" -mindepth 2 -name '*.rpm' -exec mv {} "$DIST/" \;
    find "$DIST" -mindepth 1 -type d -empty -delete
}

inside_arch() {
    pacman -Syu --noconfirm --needed -q base-devel >/dev/null
    id builder >/dev/null 2>&1 || useradd -m builder
    echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder
    local work=/home/builder/pkg pkgver="$VERSION"
    [[ -n "$SNAP_SHA" ]] && pkgver="$VERSION.r$SNAP_N.g$SNAP_SHA"
    mkdir -p "$work"
    cp "$TARBALL" "$work/"
    # Same PKGBUILD as the AUR release package, pointed at the local tarball.
    sed -e "s|^pkgver=.*|pkgver=$pkgver|" \
        -e "s|^source=.*|source=(\"rigs-$VERSION.tar.gz\")|" \
        -e "s|\"\$pkgname-\$pkgver\"|\"rigs-$VERSION\"|" \
        "$ROOT/packaging/arch/rigs/PKGBUILD" > "$work/PKGBUILD"
    chown -R builder: "$work"
    su builder -c "cd $work && makepkg -s --noconfirm --needed"
    cp "$work"/rigs-*.pkg.tar.zst "$DIST/"
}

in_container() { # format image
    local format="$1" image="$2"
    command -v podman >/dev/null || die "podman is required (or run with --inside in the right distro)"
    echo "=== $format in $image ==="
    podman run --rm -v "$ROOT:/src:Z" -v "$DIST:/dist:Z" \
        -e VERSION="$VERSION" -e SNAP_N="$SNAP_N" -e SNAP_SHA="$SNAP_SHA" -e DIST=/dist \
        "$image" bash /src/scripts/package.sh --inside "$format"
}

if [[ "${1:-}" == "--inside" ]]; then
    snapshot_info
    [[ -f "$TARBALL" ]] || make_tarball
    case "${2:-}" in
        deb) inside_deb ;; rpm) inside_rpm ;; arch) inside_arch ;;
        *) die "usage: package.sh --inside deb|rpm|arch" ;;
    esac
    exit 0
fi

target="${1:-}"
case "$target" in deb|rpm|arch|all) ;; *) die "usage: package.sh deb|rpm|arch|all" ;; esac
snapshot_info
make_tarball
[[ "$target" == deb || "$target" == all ]] && in_container deb "$DEB_IMAGE"
[[ "$target" == rpm || "$target" == all ]] && in_container rpm "$RPM_IMAGE"
[[ "$target" == arch || "$target" == all ]] && in_container arch "$ARCH_IMAGE"
echo "=== packages in $DIST ==="
ls -1 "$DIST"
