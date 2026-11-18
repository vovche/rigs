using GLib.Intl;

/* host_overview.vala — the "Host Overview" group: host CPU and RAM with sparklines. */
namespace Rigs {
    public class HostOverview : Adw.PreferencesGroup {
        private Adw.ActionRow cpu_row;
        private SmoothSparkline cpu_sparkline;
        private Adw.ActionRow ram_row;
        private SmoothSparkline ram_sparkline;

        construct {
            this.title = _("Host Overview");
            this.description = _("Overall CPU and RAM usage on your host machine");

            cpu_row = new Adw.ActionRow();
            cpu_row.title = _("CPU Usage");
            cpu_row.subtitle = _("Host CPU load: --%");
            cpu_row.add_prefix(new Gtk.Image.from_icon_name("computer-symbolic"));
            cpu_sparkline = new SmoothSparkline(0.12, 0.55, 1.0, 25, 120, 34); // vivid blue
            cpu_row.add_suffix(cpu_sparkline);
            this.add(cpu_row);

            ram_row = new Adw.ActionRow();
            ram_row.title = _("Memory (RAM)");
            ram_row.subtitle = _("Host RAM: -- / -- GB");
            ram_row.add_prefix(new Gtk.Image.from_icon_name("drive-harddisk-symbolic"));
            ram_sparkline = new SmoothSparkline(0.64, 0.28, 0.96, 25, 120, 34); // vivid violet
            ram_row.add_suffix(ram_sparkline);
            this.add(ram_row);
        }

        public void update(HostStatus host) {
            cpu_row.subtitle = _("Host CPU load: %.1f%%").printf(host.cpu_pct);
            cpu_sparkline.add_value(host.cpu_pct);
            ram_row.subtitle = _("Host RAM: %.2f / %.1f GB (%.0f%%)").printf(host.ram_used_gb, host.ram_total_gb, host.ram_pct);
            ram_sparkline.add_value(host.ram_pct);
        }
    }
}
