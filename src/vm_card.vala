/* vm_card.vala — Expander card for a virtual machine or container in Rigs */

namespace Rigs {

    public class VmCard : Adw.ExpanderRow {
        public VmModel vm { get; construct; }

        public signal void start_requested(VmModel vm);
        public signal void stop_requested(VmModel vm);
        public signal void connect_requested(VmModel vm);
        public signal void remove_requested(VmModel vm);

        private Gtk.Label status_lbl;
        private Gtk.Button start_btn;
        private Gtk.Button connect_btn;
        private Gtk.Button stop_btn;

        private Adw.ActionRow cpu_row;
        private Gtk.ProgressBar cpu_progress;
        private Adw.ActionRow ram_row;

        public VmCard(VmModel vm) {
            Object(vm: vm);
        }

        construct {
            this.title = vm.name;
            this.subtitle = vm.subtitle;
            this.add_prefix(new Gtk.Image.from_icon_name(vm.icon));

            // Status label badge
            status_lbl = new Gtk.Label("STOPPED");
            status_lbl.valign = Gtk.Align.CENTER;
            status_lbl.add_css_class("status-stopped");
            this.add_suffix(status_lbl);

            // Button box
            var btn_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            btn_box.valign = Gtk.Align.CENTER;

            start_btn = new Gtk.Button.with_label("Start");
            start_btn.icon_name = "media-playback-start-symbolic";
            start_btn.add_css_class("suggested-action");
            start_btn.clicked.connect(() => { start_requested(vm); });
            btn_box.append(start_btn);

            connect_btn = new Gtk.Button.with_label("Connect");
            connect_btn.icon_name = "display-symbolic";
            connect_btn.add_css_class("suggested-action");
            connect_btn.visible = false;
            connect_btn.clicked.connect(() => { connect_requested(vm); });
            btn_box.append(connect_btn);

            stop_btn = new Gtk.Button.from_icon_name("media-playback-stop-symbolic");
            stop_btn.tooltip_text = "Stop";
            stop_btn.add_css_class("destructive-action");
            stop_btn.visible = false;
            stop_btn.clicked.connect(() => { stop_requested(vm); });
            btn_box.append(stop_btn);

            this.add_suffix(btn_box);

            // Child rows when expanded
            cpu_row = new Adw.ActionRow();
            cpu_row.title = "VM CPU Usage";
            cpu_row.subtitle = "0.0%";
            cpu_progress = new Gtk.ProgressBar();
            cpu_progress.valign = Gtk.Align.CENTER;
            cpu_progress.hexpand = true;
            cpu_progress.set_size_request(120, -1);
            cpu_row.add_suffix(cpu_progress);
            this.add_row(cpu_row);

            ram_row = new Adw.ActionRow();
            ram_row.title = "Host RAM Usage";
            ram_row.subtitle = "0 MB";
            ram_row.add_suffix(new Gtk.Image.from_icon_name("media-memory-symbolic"));
            this.add_row(ram_row);

            var endpoint_row = new Adw.ActionRow();
            endpoint_row.title = "Services and Ports";
            endpoint_row.subtitle = (vm.details.length > 0) ? vm.details : "None";
            this.add_row(endpoint_row);

            var dir_row = new Adw.ActionRow();
            dir_row.title = "Working Directory";
            dir_row.subtitle = (vm.dir.length > 0) ? vm.dir : "None";
            this.add_row(dir_row);

            var remove_row = new Adw.ActionRow();
            remove_row.title = "Remove from Rigs";
            var remove_btn = new Gtk.Button.with_label("Remove");
            remove_btn.add_css_class("destructive-action");
            remove_btn.add_css_class("flat");
            remove_btn.clicked.connect(() => { remove_requested(vm); });
            remove_row.add_suffix(remove_btn);
            this.add_row(remove_row);
        }

        public void update_status(VmStatus status) {
            if (status.running) {
                status_lbl.label = "RUNNING";
                status_lbl.remove_css_class("status-stopped");
                status_lbl.add_css_class("status-running");

                start_btn.visible = false;
                connect_btn.visible = true;
                stop_btn.visible = true;
            } else {
                status_lbl.label = "STOPPED";
                status_lbl.remove_css_class("status-running");
                status_lbl.add_css_class("status-stopped");

                start_btn.visible = true;
                connect_btn.visible = false;
                stop_btn.visible = false;
            }

            cpu_row.subtitle = "CPU: %.1f%%".printf(status.cpu_pct);
            cpu_progress.fraction = (status.cpu_pct / 100.0).clamp(0.0, 1.0);
            ram_row.subtitle = "Memory: " + status.ram_str;
        }
    }
}
