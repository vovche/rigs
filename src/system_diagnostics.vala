/* system_diagnostics.vala — System and packaging diagnostics generator for Rigs */

namespace Rigs {
    public class SystemDiagnostics : Object {
        public static string get_report() {
            var sb = new StringBuilder();
            sb.append("=== Rigs Diagnostics Report ===\n\n");

            // 1. Application info
            sb.append("### Application\n");
            sb.append_printf("- Version: %s\n", "1.0.0");
            sb.append("- Architecture: Native Vala (GObject/C compiled)\n");

            // 2. Packaging & Sandbox detection
            sb.append("\n### Packaging & Distribution\n");
            string? snap = Environment.get_variable("SNAP");
            string? flatpak = Environment.get_variable("FLATPAK_ID");

            if (snap != null) {
                sb.append("- Channel: Snap Package (Snap Store)\n");
                sb.append_printf("- Snap Name: %s\n", Environment.get_variable("SNAP_NAME") ?? "unknown");
                sb.append_printf("- Snap Version: %s\n", Environment.get_variable("SNAP_VERSION") ?? "unknown");
                sb.append_printf("- Snap Revision: %s\n", Environment.get_variable("SNAP_REVISION") ?? "unknown");
                sb.append_printf("- Snap Architecture: %s\n", Environment.get_variable("SNAP_ARCH") ?? "unknown");
                sb.append("- Confinement: strict (plugs: system-observe, home, network, removable-media)\n");
                sb.append_printf("- Snap Root: %s\n", snap);
            } else if (flatpak != null || FileUtils.test("/.flatpak-info", FileTest.EXISTS)) {
                sb.append("- Channel: Flatpak Sandbox\n");
                sb.append_printf("- App ID: %s\n", flatpak ?? "unknown");
                sb.append("- Runtime: GNOME Platform\n");
            } else {
                sb.append("- Channel: Native Package / Compiled from Source\n");
                try {
                    string exe = FileUtils.read_link("/proc/self/exe");
                    sb.append_printf("- Executable Path: %s\n", exe);
                } catch (Error e) {
                    sb.append("- Executable Path: (unknown)\n");
                }
            }

            // 3. Operating System & Kernel
            sb.append("\n### Operating System & Kernel\n");
            string os_name = "Linux";
            try {
                string os_release;
                if (FileUtils.get_contents("/etc/os-release", out os_release)) {
                    foreach (string line in os_release.split("\n")) {
                        if (line.has_prefix("PRETTY_NAME=")) {
                            os_name = line.substring(12).replace("\"", "").strip();
                            break;
                        }
                    }
                }
            } catch (Error e) {}
            sb.append_printf("- OS: %s\n", os_name);

            Posix.utsname u = Posix.utsname();
            sb.append_printf("- Kernel: %s %s (%s)\n", u.sysname, u.release, u.machine);

            // 4. Desktop & Session
            sb.append("\n### Desktop & Windowing\n");
            sb.append_printf("- Display Server: %s\n", Environment.get_variable("XDG_SESSION_TYPE") ?? "unknown");
            sb.append_printf("- Desktop Environment: %s\n", Environment.get_variable("XDG_CURRENT_DESKTOP") ?? "unknown");
            sb.append_printf("- GTK Version: %u.%u.%u\n", Gtk.get_major_version(), Gtk.get_minor_version(), Gtk.get_micro_version());
            sb.append_printf("- Libadwaita Version: %u.%u.%u\n", Adw.get_major_version(), Adw.get_minor_version(), Adw.get_micro_version());
            sb.append_printf("- GLib Version: %u.%u.%u\n", GLib.Version.major, GLib.Version.minor, GLib.Version.micro);

            // 5. Drivers & Tooling
            sb.append("\n### Virtualization & Container Tooling\n");
            check_binary(sb, "QEMU x86_64", "qemu-system-x86_64");
            check_binary(sb, "QEMU aarch64", "qemu-system-aarch64");
            check_binary(sb, "Socat (QEMU Monitor)", "socat");
            check_binary(sb, "Podman", "podman");
            check_binary(sb, "Docker", "docker");
            check_binary(sb, "Docker Compose", "docker-compose");

            bool kvm_exists = FileUtils.test("/dev/kvm", FileTest.EXISTS);
            if (kvm_exists) {
                int fd = Posix.open("/dev/kvm", Posix.O_RDWR);
                if (fd >= 0) {
                    Posix.close(fd);
                    sb.append("- Hardware Acceleration (/dev/kvm): Available (Read/Write OK)\n");
                } else {
                    sb.append("- Hardware Acceleration (/dev/kvm): Present (Permission Denied - check kvm group)\n");
                }
            } else {
                sb.append("- Hardware Acceleration (/dev/kvm): Not Present / Not accessible\n");
            }

            return sb.str;
        }

        private static void check_binary(StringBuilder sb, string label, string bin_name) {
            string? path = Environment.find_program_in_path(bin_name);
            if (path != null) {
                sb.append_printf("- %s: %s (Found)\n", label, path);
            } else {
                sb.append_printf("- %s: Not found in PATH\n", label);
            }
        }
    }
}
