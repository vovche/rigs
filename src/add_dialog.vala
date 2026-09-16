using GLib.Intl;

namespace Rigs {

    public class AddDialog : Adw.Dialog {
        public signal void vm_added(VmModel new_vm);

        private Adw.EntryRow name_row;
        private Adw.EntryRow sub_row;
        private Adw.ComboRow type_row;
        private Adw.EntryRow dir_row;
        private Adw.EntryRow id_row;
        private Adw.EntryRow start_row;
        private Adw.EntryRow stop_row;
        private Adw.EntryRow connect_row;
        private Adw.EntryRow details_row;

        private Gtk.Window parent_window;

        public AddDialog(Gtk.Window parent) {
            this.parent_window = parent;
            this.set_title(_("Add Virtual Machine"));
            this.set_content_width(480);
            this.set_content_height(560);

            build_ui();
        }

        private void build_ui() {
            var root = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            this.set_child(root);

            var header = new Adw.HeaderBar();
            root.append(header);

            var cancel_btn = new Gtk.Button.with_label(_("Cancel"));
            cancel_btn.clicked.connect(() => { this.close(); });
            header.pack_start(cancel_btn);

            var add_btn = new Gtk.Button.with_label(_("Add"));
            add_btn.add_css_class("suggested-action");
            add_btn.clicked.connect(on_submit);
            header.pack_end(add_btn);

            var scrolled = new Gtk.ScrolledWindow();
            scrolled.vexpand = true;
            root.append(scrolled);

            var page = new Adw.PreferencesPage();
            scrolled.set_child(page);

            var grp = new Adw.PreferencesGroup();
            grp.title = _("Machine Details");
            grp.description = _("Configure your virtual machine or container");
            page.add(grp);

            name_row = new Adw.EntryRow();
            name_row.title = _("VM Name");
            grp.add(name_row);

            sub_row = new Adw.EntryRow();
            sub_row.title = _("Subtitle / OS");
            sub_row.text = _("Linux • Custom VM");
            grp.add(sub_row);

            type_row = new Adw.ComboRow();
            type_row.title = _("Type");
            var model = new Gtk.StringList(new string[] { _("Podman / Docker Compose"), _("Direct QEMU Script") });
            type_row.model = model;
            type_row.notify["selected"].connect(on_type_changed);
            grp.add(type_row);

            dir_row = new Adw.EntryRow();
            dir_row.title = _("Working Directory");
            dir_row.text = "/home/why/src/vms/";
            var browse_btn = new Gtk.Button.from_icon_name("folder-open-symbolic");
            browse_btn.add_css_class("flat");
            browse_btn.tooltip_text = _("Browse Directory");
            browse_btn.clicked.connect(on_browse_clicked);
            dir_row.add_suffix(browse_btn);
            grp.add(dir_row);

            id_row = new Adw.EntryRow();
            id_row.title = _("Container Name");
            grp.add(id_row);

            start_row = new Adw.EntryRow();
            start_row.title = _("Start Command");
            start_row.text = "docker compose up -d";
            grp.add(start_row);

            stop_row = new Adw.EntryRow();
            stop_row.title = _("Stop Command");
            stop_row.text = "docker compose down";
            grp.add(stop_row);

            connect_row = new Adw.EntryRow();
            connect_row.title = _("Connect Command");
            connect_row.text = "remmina -c ...";
            grp.add(connect_row);

            details_row = new Adw.EntryRow();
            details_row.title = _("Ports and Services");
            details_row.text = "RDP :3389 • SSH :22";
            grp.add(details_row);
        }

        private void on_browse_clicked() {
            var dialog = new Gtk.FileDialog();
            dialog.title = _("Select VM Directory");

            string current_path = dir_row.text.strip();
            if (FileUtils.test(current_path, FileTest.IS_DIR)) {
                dialog.initial_folder = File.new_for_path(current_path);
            }

            dialog.select_folder.begin(parent_window, null, (obj, res) => {
                try {
                    var folder = dialog.select_folder.end(res);
                    if (folder != null) {
                        string path = folder.get_path();
                        dir_row.text = path;
                        auto_detect(path);
                    }
                } catch (Error e) {
                    // Canceled or failed
                }
            });
        }

        private void auto_detect(string path) {
            string basename = Path.get_basename(path);
            if (name_row.text.strip().length == 0) {
                name_row.text = basename;
            }

            bool has_compose = FileUtils.test(Path.build_filename(path, "compose.yaml"), FileTest.EXISTS) ||
                               FileUtils.test(Path.build_filename(path, "docker-compose.yml"), FileTest.EXISTS);
            bool has_qemu = FileUtils.test(Path.build_filename(path, "run-vm.sh"), FileTest.EXISTS);

            if (has_compose) {
                type_row.selected = 0;
                id_row.text = basename + "-vm";
                start_row.text = "docker compose up -d";
                stop_row.text = "docker compose down";
            } else if (has_qemu) {
                type_row.selected = 1;
                id_row.text = basename + "-qemu";
                start_row.text = "./run-vm.sh";
                stop_row.text = "pkill -f " + basename + "-qemu";
                connect_row.text = "remote-viewer spice://127.0.0.1:5930";
            }
        }

        private void on_type_changed() {
            bool is_compose = (type_row.selected == 0);
            if (is_compose) {
                id_row.title = _("Container Name");
                start_row.text = "docker compose up -d";
                stop_row.text = "docker compose down";
                connect_row.text = "remmina -c ...";
            } else {
                id_row.title = _("Process Name");
                start_row.text = "./run-vm.sh";
                stop_row.text = "pkill -f ...";
                connect_row.text = "remote-viewer spice://127.0.0.1:5930";
            }
        }

        private void on_submit() {
            string name = name_row.text.strip();
            if (name.length == 0) return;

            bool is_compose = (type_row.selected == 0);
            string slug = name.down().replace(" ", "_");

            var vm = new VmModel();
            vm.id = slug;
            vm.name = name;
            vm.subtitle = sub_row.text.strip();
            vm.vm_type = is_compose ? "compose" : "qemu";
            vm.icon = is_compose ? "network-server-symbolic" : "computer-symbolic";
            vm.dir = dir_row.text.strip();
            vm.start_cmd = start_row.text.strip();
            vm.stop_cmd = stop_row.text.strip();
            vm.connect_cmd = connect_row.text.strip();
            vm.details = details_row.text.strip();

            if (is_compose) {
                vm.container_name = id_row.text.strip();
            } else {
                vm.process_name = id_row.text.strip();
                vm.monitor_socket = "/tmp/" + slug + "-monitor.sock";
            }

            this.close();
            vm_added(vm);
        }
    }
}
