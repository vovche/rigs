# Packaging and operations

## What works where

| Feature | Native (`./build.sh`, distro package) | Snap classic | Snap strict + Docker Snap | Flatpak |
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
