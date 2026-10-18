using GLib.Intl;

namespace Rigs {

    public class VmCard : Adw.ExpanderRow {
        public VmModel vm { get; construct; }

        public signal void start_requested(VmModel vm);
        public signal void stop_requested(VmModel vm);
        public signal void connect_requested(VmModel vm);
        public signal void remove_requested(VmModel vm);
        public signal void insert_iso_requested(VmModel vm);
        public signal void eject_iso_requested(VmModel vm);

        private Gtk.Label status_lbl;
        private Gtk.Button start_btn;
        private Gtk.Button connect_btn;
        private Gtk.Button stop_btn;

        private Adw.ActionRow cpu_row;
        private SmoothSparkline cpu_sparkline;
        private Adw.ActionRow ram_row;
        private SmoothSparkline ram_sparkline;
        private Adw.ActionRow iso_row;
        private Gtk.Button eject_btn;

        public VmCard(VmModel vm) {
            Object(vm: vm);
        }

        construct {
            this.title = vm.name;
            this.subtitle = vm.subtitle;
            this.add_prefix(new Gtk.Image.from_icon_name(vm.icon));

            // Status label badge
            status_lbl = new Gtk.Label(_("STOPPED"));
            status_lbl.valign = Gtk.Align.CENTER;
            status_lbl.add_css_class("status-stopped");
            this.add_suffix(status_lbl);

            // Button box
            var btn_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            btn_box.valign = Gtk.Align.CENTER;

            start_btn = new Gtk.Button.with_label(_("Start"));
            start_btn.icon_name = "media-playback-start-symbolic";
            start_btn.add_css_class("suggested-action");
            start_btn.clicked.connect(() => { start_requested(vm); });
            btn_box.append(start_btn);

            connect_btn = new Gtk.Button.with_label(_("Connect"));
            connect_btn.icon_name = "display-symbolic";
            connect_btn.add_css_class("suggested-action");
            connect_btn.visible = false;
            connect_btn.clicked.connect(() => { connect_requested(vm); });
            btn_box.append(connect_btn);

            stop_btn = new Gtk.Button.from_icon_name("media-playback-stop-symbolic");
            stop_btn.tooltip_text = _("Stop");
            stop_btn.add_css_class("destructive-action");
            stop_btn.visible = false;
            stop_btn.clicked.connect(() => { stop_requested(vm); });
            btn_box.append(stop_btn);

            this.add_suffix(btn_box);

            // Child rows when expanded
            // 1. CPU with Resources-style sparkline (Vivid Blue, dynamic auto-scale with 15% min floor)
            cpu_row = new Adw.ActionRow();
            cpu_row.title = _("VM CPU Usage");
            cpu_row.subtitle = "0.0%";
            cpu_sparkline = new SmoothSparkline(0.12, 0.55, 1.0, 25, 130, 32, true, 15.0);
            cpu_row.add_suffix(cpu_sparkline);
            this.add_row(cpu_row);

            // 2. RAM with Resources-style Bezier sparkline (Vivid Violet)
            ram_row = new Adw.ActionRow();
            ram_row.title = vm.vm_type == "qemu"
                ? _("Host Memory / Allocated RAM") : _("VM Memory Usage");
            if (vm.vm_type == "qemu") {
                ram_row.tooltip_text = _("QEMU process memory on the host / RAM allocated to the VM. Usage inside the guest OS is not available.");
            }
            ram_row.subtitle = "0 MB";
            ram_sparkline = new SmoothSparkline(0.64, 0.28, 0.96, 25, 130, 32, true);
            // RSS / allocated guest RAM is not a guest memory usage percentage.
            ram_sparkline.visible = vm.vm_type != "qemu";
            ram_row.add_suffix(ram_sparkline);
            this.add_row(ram_row);

            // 3. Optical Drive (ISO)
            iso_row = new Adw.ActionRow();
            iso_row.title = _("Optical Drive (ISO)");
            iso_row.add_prefix(new Gtk.Image.from_icon_name("media-optical-symbolic"));
            update_iso_subtitle();

            var iso_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            iso_box.valign = Gtk.Align.CENTER;

            var insert_btn = new Gtk.Button.with_label(_("Insert…"));
            insert_btn.icon_name = "media-optical-symbolic";
            insert_btn.add_css_class("flat");
            insert_btn.clicked.connect(() => { insert_iso_requested(vm); });
            iso_box.append(insert_btn);

            eject_btn = new Gtk.Button.with_label(_("Eject"));
            eject_btn.icon_name = "media-eject-symbolic";
            eject_btn.add_css_class("destructive-action");
            eject_btn.add_css_class("flat");
            eject_btn.visible = (vm.attached_iso.length > 0);
            eject_btn.clicked.connect(() => { eject_iso_requested(vm); });
            iso_box.append(eject_btn);

            iso_row.add_suffix(iso_box);
            this.add_row(iso_row);

            // 4. Ports & Endpoints
            var endpoint_row = new Adw.ActionRow();
            endpoint_row.title = _("Services and Ports");
            endpoint_row.subtitle = (vm.details.length > 0) ? vm.details : _("None");
            this.add_row(endpoint_row);

            // 5. Directory
            var dir_row = new Adw.ActionRow();
            dir_row.title = _("Working Directory");
            dir_row.subtitle = (vm.dir.length > 0) ? vm.dir : _("None");
            this.add_row(dir_row);

            // 6. Remove VM
            var remove_row = new Adw.ActionRow();
            remove_row.title = _("Remove from Rigs");
            var remove_btn = new Gtk.Button.with_label(_("Remove"));
            remove_btn.add_css_class("destructive-action");
            remove_btn.add_css_class("flat");
            remove_btn.clicked.connect(() => { remove_requested(vm); });
            remove_row.add_suffix(remove_btn);
            this.add_row(remove_row);
        }

        public void update_iso_subtitle() {
            if (vm.attached_iso.length > 0 && FileUtils.test(vm.attached_iso, FileTest.EXISTS)) {
                iso_row.subtitle = Path.get_basename(vm.attached_iso);
                if (eject_btn != null) eject_btn.visible = true;
            } else {
                iso_row.subtitle = _("[ No Media / Ejected ]");
                if (eject_btn != null) eject_btn.visible = false;
            }
        }

        public void update_status(VmStatus status) {
            if (status.running) {
                status_lbl.label = _("RUNNING");
                status_lbl.remove_css_class("status-stopped");
                status_lbl.add_css_class("status-running");

                start_btn.visible = false;
                connect_btn.visible = true;
                stop_btn.visible = true;
            } else {
                status_lbl.label = _("STOPPED");
                status_lbl.remove_css_class("status-running");
                status_lbl.add_css_class("status-stopped");

                start_btn.visible = true;
                connect_btn.visible = false;
                stop_btn.visible = false;
            }

            cpu_row.subtitle = _("CPU: %.1f%% (host)").printf(status.cpu_pct);
            cpu_sparkline.add_value(status.running ? status.cpu_pct : 0.0);

            if (vm.vm_type != "qemu" && status.running && status.ram_pct > 0.0) {
                ram_row.subtitle = _("Memory: %s (%.1f%%)").printf(status.ram_str, status.ram_pct);
            } else {
                ram_row.subtitle = _("Memory: %s").printf(status.ram_str);
            }
            ram_sparkline.add_value(status.running ? status.ram_pct : 0.0);
        }
    }
}
