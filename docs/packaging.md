# Packaging and operations

## What works where

| Feature | Native (.deb, .rpm, Arch, `./build.sh`) | Snap classic | Snap strict + Docker Snap | Flatpak |
|---------|:---:|:---:|:---:|:---:|
| Compose projects, user scripts | ✅ | ✅ | ❌ | not supported |
| Podman containers | ✅ | ✅ | ❌ | not supported |
| Docker containers | ✅ | ✅ | ✅ (connected interfaces) | not supported |
| libvirt domains (`virsh`) | ✅ | ✅ | ❌ | not supported |
| Scripted QEMU status (`/proc`) | ✅ | ✅ | ❌ | not supported |
| HMP/QMP sockets (ISO, powerdown, guest RAM) | ✅ | ✅ | ❌ | not supported |
| GNOME Shell search | ✅ | ✅ | ✅ | not supported |

Strict Snap needs:

```sh
sudo snap connect rigs:docker docker:docker-daemon
sudo snap connect rigs:docker-executables docker:docker-executables
```

Anything a mode cannot do is reported as an explicit "Not supported" issue, never silently
skipped (`HostCommand.prepare` throws `IOError.NOT_SUPPORTED`).

**Flatpak is deliberately not supported:** the sandbox has its own PID namespace (no host
`/proc`) and a private `/tmp` (no QEMU sockets), and the host access needed to work around
both defeats the sandbox. Inside Flatpak, every host command fails with that explanation.

## Distribution packages

| Format | Files | Built on | Installs on |
|--------|-------|----------|-------------|
| .deb | `debian/` (debhelper + meson, native source format) | Ubuntu 24.04 container | Ubuntu 24.04+, Debian 13+ |
| .rpm | `packaging/rpm/rigs.spec` | Fedora 42 container | Fedora 42+ |
| Arch | `packaging/arch/rigs/PKGBUILD` (release), `packaging/arch/rigs-git/PKGBUILD` (main) | Arch container | Arch and derivatives |

```sh
scripts/package.sh deb      # or rpm, arch, all  → dist/
scripts/package.sh arch-install                 # on Arch: build from this clone + pacman -U
```

- Packages are built from `git archive HEAD`: commit first; uncommitted changes are not packaged.
- Every build runs `meson test` (unit tests, lint, lint self-test). A red build means no package.
- HEAD not at tag `v<version>` gives snapshot versions (`0.9.0+git16.be2263d`, `0.9.0-1.git16.be2263d`,
  `0.9.0.r16.gbe2263d`), which sort above the last release and below the next one.
- Base images can be overridden: `DEB_IMAGE=debian:trixie scripts/package.sh deb`.
- CI (`.github/workflows/packages.yml`) runs the same script per format on every `v*` tag and
  attaches the packages to the GitHub release; it can also be started by hand (workflow_dispatch).

### Releasing a version

1. Bump the version in `meson.build`, `debian/changelog` (new entry: `dch -v X.Y.Z`),
   `packaging/rpm/rigs.spec` (Version + `%changelog`), both `packaging/arch/*/PKGBUILD`,
   `snap/snapcraft.yaml` and a new `<release>` in the metainfo. Lint VERSION-02 fails until all match.
2. Write the release notes in `docs/releases/X.Y.Z.md` (the release workflow refuses to publish without them).
3. `./build.sh`, then `scripts/package.sh all` and install-test the results.
4. Tag and push: `git tag -a vX.Y.Z -m "Rigs X.Y.Z" && git push origin main vX.Y.Z`.
   `.github/workflows/packages.yml` then builds deb/rpm/Arch + source tarball + SHA256SUMS,
   publishes the GitHub release, and calls `pages.yml`, which re-renders the website with
   links to exactly those files.
5. AUR (`rigs`): copy `packaging/arch/rigs/PKGBUILD` into the AUR repo, run `updpkgsums` and
   `makepkg --printsrcinfo > .SRCINFO`, commit, push.

## Website (GitHub Pages)

`site/` is the landing page: `template.html`, `i18n/en.json` + `i18n/uk.json` (same keys),
`style.css`, `site.js`. `scripts/build_site.py` renders `/` (English) and `/uk/` (Ukrainian)
with the version, date, file names, sizes and download links of the latest release; it fails on
a missing translation key, asset or placeholder (meson test `site` renders a fixture release).

- Language: `/` redirects to `/uk/` when the browser prefers Ukrainian or Russian, unless the
  visitor picked a language with the switch (remembered in localStorage).
- Preview locally: `scripts/build_site.py --release-json tests/fixtures/release.json --out /tmp/site`
  and `python3 -m http.server -d /tmp/site`.
- Text changes between releases: commit, then `gh workflow run pages.yml`.

## Logs and diagnostics

- `rigs --diagnostics` prints the packaging mode, tool versions and paths (also in About → Troubleshooting).
- `G_MESSAGES_DEBUG=all rigs` shows GLib debug output; warnings go to `journalctl --user -t rigs`
  (or the terminal). User-facing failures are never only in the log: they appear as a toast and
  a warning icon on the card.
- Configuration: `~/.config/rigs/vms.json` (resources), `~/.config/rigs/state.json` (window).

## Trying a build without touching your configuration

```sh
./build.sh      # build, unit tests, lint, install to ~/.local
./run.sh        # run the build with a temporary, empty config directory
./run.sh --keep # same, but keep the temporary directory and print its path
```
