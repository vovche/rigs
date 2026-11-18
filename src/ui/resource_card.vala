using GLib.Intl;

namespace Rigs {

    public class ResourceCard : Adw.ExpanderRow {
        public Resource resource { get; construct; }

        public signal void start_requested(Resource resource);
        public signal void stop_requested(Resource resource);
        public signal void connect_requested(Resource resource);
        public signal void remove_requested(Resource resource);
        public signal void insert_iso_requested(Resource resource);
        public signal void eject_iso_requested(Resource resource);
        public signal void guest_tools_requested(Resource resource, GuestMemoryState state);
        public signal void issue_details_requested(Resource resource, ResourceIssue issue);
        // Re-emitted from the model so listeners live and die with the card.
        public signal void issue_raised(Resource resource, ResourceIssue issue);

        // Models outlive cards (Undo restores the same Resource). Every connection to
        // `vm` must go through track() so detach() can remove it; see docs/guardrails.md (MODEL-01).
        private ulong[] model_handlers = {};

        private Gtk.Label status_lbl;
        private Gtk.Button issue_btn;
        private Gtk.Button start_btn;
        private Gtk.Button connect_btn;
        private Gtk.Button stop_btn;
        private Gtk.Button guest_settings_btn;

        private Adw.ActionRow cpu_row;
        private SmoothSparkline cpu_sparkline;
        private Adw.ActionRow ram_row;
        private Adw.ActionRow guest_ram_row;
        private SmoothSparkline ram_sparkline;
        private Adw.ActionRow iso_row;
        private Gtk.Button eject_btn;
        private GuestMemoryState guest_state = GuestMemoryState.NOT_CONFIGURED;

        public ResourceCard(Resource resource) {
            Object(resource: resource);
        }

        construct {
            this.use_markup = false;
            this.title = resource.name;
            this.subtitle = resource.subtitle;
            this.add_prefix(new Gtk.Image.from_icon_name(resource.icon));

            // Status label badge
            status_lbl = new Gtk.Label(_("STOPPED"));
            status_lbl.valign = Gtk.Align.CENTER;
            status_lbl.add_css_class("status-stopped");
            this.add_suffix(status_lbl);

            issue_btn = new Gtk.Button.from_icon_name("dialog-warning-symbolic");
            issue_btn.add_css_class("flat");
            issue_btn.valign = Gtk.Align.CENTER;
            issue_btn.visible = false;
            issue_btn.clicked.connect(() => {
                if (resource.last_issue != null) issue_details_requested(resource, resource.last_issue);
            });
            this.add_suffix(issue_btn);
            track(resource.notify["last-issue"].connect(refresh_issue));
            track(resource.issue_raised.connect((issue) => { issue_raised(resource, issue); }));
            refresh_issue();

            // Button box
            var btn_box = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
            btn_box.valign = Gtk.Align.CENTER;

            start_btn = new Gtk.Button.with_label(_("Start"));
            start_btn.icon_name = "media-playback-start-symbolic";
            start_btn.add_css_class("suggested-action");
            start_btn.clicked.connect(() => { start_requested(resource); });
            btn_box.append(start_btn);

            connect_btn = new Gtk.Button.with_label(_("Connect"));
            connect_btn.icon_name = "display-symbolic";
            connect_btn.add_css_class("suggested-action");
            connect_btn.visible = false;
            connect_btn.clicked.connect(() => { connect_requested(resource); });
            btn_box.append(connect_btn);

            stop_btn = new Gtk.Button.from_icon_name("media-playback-stop-symbolic");
            stop_btn.tooltip_text = _("Stop");
            stop_btn.add_css_class("destructive-action");
            stop_btn.visible = false;
            stop_btn.clicked.connect(() => { stop_requested(resource); });
            btn_box.append(stop_btn);
            guest_settings_btn = new Gtk.Button.from_icon_name("emblem-system-symbolic");
            guest_settings_btn.tooltip_text = _("Set Up Guest Integration");
            guest_settings_btn.clicked.connect(() => { guest_tools_requested(resource, guest_state); });
            btn_box.append(guest_settings_btn);

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
            ram_row.title = resource.kind == ResourceKind.LIBVIRT ? _("Allocated RAM") : resource.kind == ResourceKind.QEMU
                ? _("Host Memory / Allocated RAM") : _("Host Memory");
            if (resource.kind == ResourceKind.QEMU) {
                ram_row.tooltip_text = _("QEMU process memory on the host / RAM allocated to the VM. Usage inside the guest OS is not available.");
            }
            ram_row.subtitle = "0 MB";
            this.add_row(ram_row);

            guest_ram_row = new Adw.ActionRow();
            guest_ram_row.title = _("Guest Memory Usage");
            guest_ram_row.subtitle = _("Guest statistics unavailable");
            guest_ram_row.visible = resource.qmp_socket.length > 0 || resource.kind == ResourceKind.QEMU || resource.kind == ResourceKind.LIBVIRT || resource.guest_os.length > 0;
            guest_settings_btn.visible = !guest_ram_row.visible;
            var guest_setup = new Gtk.Button.from_icon_name("emblem-system-symbolic");
            guest_setup.valign = Gtk.Align.CENTER;
            guest_setup.tooltip_text = _("Set Up Guest Integration");
            guest_setup.clicked.connect(() => { guest_tools_requested(resource, guest_state); });
            guest_ram_row.add_suffix(guest_setup);
            ram_sparkline = new SmoothSparkline(0.64, 0.28, 0.96, 25, 130, 32);
            guest_ram_row.add_suffix(ram_sparkline);
            this.add_row(guest_ram_row);

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
            insert_btn.clicked.connect(() => { insert_iso_requested(resource); });
            iso_box.append(insert_btn);

            eject_btn = new Gtk.Button.with_label(_("Eject"));
            eject_btn.icon_name = "media-eject-symbolic";
            eject_btn.add_css_class("destructive-action");
            eject_btn.add_css_class("flat");
            eject_btn.visible = (resource.attached_iso.length > 0);
            eject_btn.clicked.connect(() => { eject_iso_requested(resource); });
            iso_box.append(eject_btn);

            iso_row.add_suffix(iso_box);
            this.add_row(iso_row);
            iso_row.visible = resource.kind == ResourceKind.QEMU;

            // 4. Ports & Endpoints
            var endpoint_row = new Adw.ActionRow();
            endpoint_row.title = _("Services and Ports");
            endpoint_row.subtitle = (resource.details.length > 0) ? resource.details : _("None");
            this.add_row(endpoint_row);

            // 5. Directory
            var dir_row = new Adw.ActionRow();
            dir_row.title = _("Working Directory");
            dir_row.subtitle = (resource.dir.length > 0) ? resource.dir : _("None");
            this.add_row(dir_row);
            dir_row.visible = resource.dir.length > 0;

            // 6. Remove VM
            var remove_row = new Adw.ActionRow();
            remove_row.title = _("Remove from Rigs");
            var remove_btn = new Gtk.Button.with_label(_("Remove"));
            remove_btn.add_css_class("destructive-action");
            remove_btn.add_css_class("flat");
            remove_btn.clicked.connect(() => { remove_requested(resource); });
            remove_row.add_suffix(remove_btn);
            this.add_row(remove_row);
        }

        public void update_iso_subtitle() {
            if (resource.attached_iso.length > 0 && FileUtils.test(resource.attached_iso, FileTest.EXISTS)) {
                iso_row.subtitle = Path.get_basename(resource.attached_iso);
                if (eject_btn != null) eject_btn.visible = true;
            } else {
                iso_row.subtitle = _("[ No Media / Ejected ]");
                if (eject_btn != null) eject_btn.visible = false;
            }
        }

        private void track(ulong handler_id) {
            model_handlers += handler_id;
        }

        // Call before dropping the card; otherwise the model keeps it alive and signals reach it.
        public void detach() {
            foreach (ulong id in model_handlers) SignalHandler.disconnect(resource, id);
            model_handlers = {};
        }

        private void refresh_issue() {
            var issue = resource.last_issue;
            issue_btn.visible = issue != null;
            if (issue != null) issue_btn.tooltip_text = "%s: %s".printf(ResourceIssue.headline(issue.operation, resource.name), issue.title);
        }

        public void update_status(ResourceStatus status) {
            guest_state = status.guest_memory_state;
            guest_ram_row.visible = resource.qmp_socket.length > 0 || resource.kind == ResourceKind.QEMU || resource.kind == ResourceKind.LIBVIRT || resource.guest_os.length > 0;
            guest_settings_btn.visible = !guest_ram_row.visible;
            if (!status.status_available) {
                status_lbl.label = _("UNAVAILABLE");
                status_lbl.remove_css_class("status-running");
                status_lbl.add_css_class("status-stopped");
                start_btn.visible = stop_btn.visible = connect_btn.visible = false;
                cpu_row.subtitle = ram_row.subtitle = _("Connection unavailable");
                guest_ram_row.subtitle = _("Guest statistics unavailable");
                ram_sparkline.visible = false;
                return;
            }
            if (status.running) {
                status_lbl.label = _("RUNNING");
                status_lbl.remove_css_class("status-stopped");
                status_lbl.add_css_class("status-running");

                start_btn.visible = false;
                connect_btn.visible = resource.kind == ResourceKind.LIBVIRT || resource.connect_cmd.length > 0;
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

            // Container usage / guest RAM is not a guest usage percentage.
            string host_memory = resource.kind == ResourceKind.COMPOSE ? status.ram_str.split(" / ")[0] : status.ram_str;
            ram_row.subtitle = _("Memory: %s").printf(host_memory);
            if (status.running && status.guest_ram_valid) {
                guest_ram_row.subtitle = _("Memory: %s (%.1f%%)").printf(status.guest_ram_str, status.guest_ram_pct);
            } else {
                guest_ram_row.subtitle = status.running ? GuestToolsDialog.describe(guest_state) : "0 MB";
            }
            ram_sparkline.visible = status.running && status.guest_ram_valid;
            ram_sparkline.add_value(status.running && status.guest_ram_valid ? status.guest_ram_pct : 0.0);
        }
    }
}
