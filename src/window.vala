using GLib.Intl;

namespace Rigs {

    public class Window : Adw.ApplicationWindow {
        private GenericArray<VmModel> vms;
        private HashTable<string, VmCard> cards;
        private SystemMonitor monitor;

        private Adw.ToastOverlay toast_overlay;
        private Adw.PreferencesGroup vm_group;
        private Adw.ActionRow host_cpu_row;
        private SmoothSparkline host_cpu_sparkline;
        private Adw.ActionRow host_ram_row;
        private SmoothSparkline host_ram_sparkline;
        private Adw.ActionRow empty_status_row;

        public Window(Adw.Application app) {
            Object(application: app);
        }

        construct {
            this.title = "Rigs";
            this.vms = ConfigManager.load_vms();
            this.cards = new HashTable<string, VmCard>(str_hash, str_equal);
            this.monitor = new SystemMonitor();

            load_window_state();
            build_ui();

            this.notify["default-width"].connect(() => { save_window_state(); });
            this.notify["default-height"].connect(() => { save_window_state(); });
            this.notify["maximized"].connect(() => { save_window_state(); });
            this.close_request.connect(on_close_request);

            monitor.updated.connect(on_monitor_updated);
            monitor.start(vms);
        }

        private void build_ui() {
            var root = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            this.set_content(root);

            var header = new Adw.HeaderBar();
            var title_widget = new Adw.WindowTitle(_("Rigs"), _("Virtual Machine and Container Hub"));
            header.title_widget = title_widget;

            var add_btn = new Gtk.Button.from_icon_name("list-add-symbolic");
            add_btn.tooltip_text = _("Add Virtual Machine (Ctrl+N)");
            add_btn.update_property(Gtk.AccessibleProperty.LABEL, _("Add Virtual Machine"));
            add_btn.clicked.connect(open_add_dialog);
            header.pack_start(add_btn);

            var menu = new Menu();
            menu.append(_("Report an Issue"), "app.report-issue");
            menu.append(_("About Rigs"), "app.about");
            menu.append(_("Quit"), "app.quit");

            var menu_btn = new Gtk.MenuButton();
            menu_btn.icon_name = "open-menu-symbolic";
            menu_btn.tooltip_text = _("Main Menu");
            menu_btn.update_property(Gtk.AccessibleProperty.LABEL, _("Main Menu"));
            menu_btn.menu_model = menu;
            header.pack_end(menu_btn);

            root.append(header);

            toast_overlay = new Adw.ToastOverlay();
            toast_overlay.vexpand = true;
            toast_overlay.hexpand = true;
            root.append(toast_overlay);

            var scrolled = new Gtk.ScrolledWindow();
            scrolled.vexpand = true;
            scrolled.hexpand = true;
            toast_overlay.set_child(scrolled);

            var clamp = new Adw.Clamp();
            clamp.maximum_size = 680;
            clamp.tightening_threshold = 520;
            scrolled.set_child(clamp);

            var page = new Adw.PreferencesPage();
            clamp.set_child(page);

            // Host Group with Resources-style Bezier sparklines
            var host_group = new Adw.PreferencesGroup();
            host_group.title = _("Host Overview");
            host_group.description = _("Overall CPU and RAM usage on your host machine");
            page.add(host_group);

            // CPU Sparkline (Blue)
            host_cpu_row = new Adw.ActionRow();
            host_cpu_row.title = _("CPU Usage");
            host_cpu_row.subtitle = _("Host CPU load: --%");
            host_cpu_row.add_prefix(new Gtk.Image.from_icon_name("computer-symbolic"));
            host_cpu_sparkline = new SmoothSparkline(0.208, 0.518, 0.894, 25, 120, 34);
            host_cpu_row.add_suffix(host_cpu_sparkline);
            host_group.add(host_cpu_row);

            // RAM Sparkline (Purple)
            host_ram_row = new Adw.ActionRow();
            host_ram_row.title = _("Memory (RAM)");
            host_ram_row.subtitle = _("Host RAM: -- / -- GB");
            host_ram_row.add_prefix(new Gtk.Image.from_icon_name("drive-harddisk-symbolic"));
            host_ram_sparkline = new SmoothSparkline(0.569, 0.255, 0.675, 25, 120, 34);
            host_ram_row.add_suffix(host_ram_sparkline);
            host_group.add(host_ram_row);

            // VM Group
            vm_group = new Adw.PreferencesGroup();
            vm_group.title = _("Virtual Machines");
            vm_group.description = _("Status, resource consumption and controls");
            page.add(vm_group);

            empty_status_row = new Adw.ActionRow();
            empty_status_row.title = _("No Virtual Machines");
            empty_status_row.subtitle = _("Click the + button above to register your first virtual machine");
            empty_status_row.add_prefix(new Gtk.Image.from_icon_name("utilities-system-monitor-symbolic"));

            for (int i = 0; i < vms.length; i++) {
                render_vm_card(vms[i]);
            }

            update_empty_state();
        }

        private void render_vm_card(VmModel vm) {
            var card = new VmCard(vm);

            card.start_requested.connect((v) => { start_vm(v); });
            card.stop_requested.connect((v) => { stop_vm(v); });
            card.connect_requested.connect((v) => { connect_vm(v); });
            card.remove_requested.connect((v) => { prompt_remove_vm(v); });
            card.insert_iso_requested.connect((v) => { choose_and_insert_iso(v, card); });
            card.eject_iso_requested.connect((v) => { eject_iso(v, card); });

            card.notify["expanded"].connect(() => { save_window_state(); });

            vm_group.add(card);
            cards.insert(vm.id, card);
        }

        public void open_add_dialog() {
            var dialog = new AddDialog(this);
            dialog.vm_added.connect((new_vm) => {
                vms.add(new_vm);
                ConfigManager.save_vms(vms);
                render_vm_card(new_vm);
                update_empty_state();
                save_window_state();

                var toast = new Adw.Toast(_("Registered '%s'").printf(new_vm.name));
                toast_overlay.add_toast(toast);
            });
            dialog.present(this);
        }

        private void update_empty_state() {
            if (vms.length == 0) {
                if (empty_status_row.get_parent() == null) {
                    vm_group.add(empty_status_row);
                }
            } else {
                if (empty_status_row.get_parent() != null) {
                    vm_group.remove(empty_status_row);
                }
            }
        }

        private void choose_and_insert_iso(VmModel vm, VmCard card) {
            var dialog = new Gtk.FileDialog();
            dialog.title = _("Select ISO Disk Image");

            var filter = new Gtk.FileFilter();
            filter.name = _("Disk Images (*.iso)");
            filter.add_pattern("*.iso");
            filter.add_pattern("*.ISO");

            var store = new ListStore(typeof(Gtk.FileFilter));
            store.append(filter);
            dialog.filters = store;
            dialog.default_filter = filter;

            dialog.open.begin(this, null, (obj, res) => {
                try {
                    var file = dialog.open.end(res);
                    if (file != null) {
                        string iso_path = file.get_path();
                        vm.attached_iso = iso_path;
                        ConfigManager.save_vms(vms);
                        card.update_iso_subtitle();

                        // Hot-swap via driver
                        Driver? driver = DriverRegistry.get_default().get_driver(vm.vm_type);
                        if (driver != null) {
                            driver.insert_iso(vm, iso_path);
                        }

                        var toast = new Adw.Toast(_("Inserted '%s' into %s").printf(Path.get_basename(iso_path), vm.name));
                        toast_overlay.add_toast(toast);
                    }
                } catch (Error e) {}
            });
        }

        private void eject_iso(VmModel vm, VmCard card) {
            vm.attached_iso = "";
            ConfigManager.save_vms(vms);
            card.update_iso_subtitle();

            // Hot-eject via driver
            Driver? driver = DriverRegistry.get_default().get_driver(vm.vm_type);
            if (driver != null) {
                driver.eject_iso(vm);
            }

            var toast = new Adw.Toast(_("Ejected optical media from %s").printf(vm.name));
            toast_overlay.add_toast(toast);
        }

        private void start_vm(VmModel vm) {
            var toast = new Adw.Toast(_("Starting %s…").printf(vm.name));
            toast_overlay.add_toast(toast);

            Driver? driver = DriverRegistry.get_default().get_driver(vm.vm_type);
            if (driver != null) {
                driver.start(vm);
            }
        }

        private void stop_vm(VmModel vm) {
            var toast = new Adw.Toast(_("Stopping %s…").printf(vm.name));
            toast_overlay.add_toast(toast);

            Driver? driver = DriverRegistry.get_default().get_driver(vm.vm_type);
            if (driver != null) {
                driver.stop(vm);
            }
        }

        private void connect_vm(VmModel vm) {
            Driver? driver = DriverRegistry.get_default().get_driver(vm.vm_type);
            if (driver != null) {
                driver.connect_vm(vm);
            }
        }

        private void prompt_remove_vm(VmModel vm) {
            var dialog = new Adw.AlertDialog(
                _("Remove '%s'?").printf(vm.name),
                _("The virtual machine will be removed from Rigs. Your files and VM disk on the host will remain untouched.")
            );
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("remove", _("Remove"));
            dialog.set_response_appearance("remove", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.set_default_response("cancel");
            dialog.set_close_response("cancel");

            dialog.response.connect((d, resp) => {
                if (resp == "remove") {
                    execute_remove(vm);
                }
            });
            dialog.present(this);
        }

        private void execute_remove(VmModel vm) {
            int idx = -1;
            for (int i = 0; i < vms.length; i++) {
                if (vms[i].id == vm.id) {
                    idx = i;
                    break;
                }
            }
            if (idx < 0) return;

            VmModel removed = vms[idx];
            vms.remove_index(idx);
            ConfigManager.save_vms(vms);

            VmCard card = cards.lookup(removed.id);
            if (card != null) {
                vm_group.remove(card);
                cards.remove(removed.id);
            }

            update_empty_state();
            save_window_state();

            var toast = new Adw.Toast(_("Removed '%s'").printf(removed.name));
            toast.button_label = _("Undo");
            toast.button_clicked.connect(() => {
                vms.insert(idx, removed);
                ConfigManager.save_vms(vms);
                render_vm_card(removed);
                update_empty_state();
                save_window_state();
            });
            toast_overlay.add_toast(toast);
        }

        private void on_monitor_updated(HostStatus host, HashTable<string, VmStatus?> vm_statuses) {
            host_cpu_row.subtitle = _("Host CPU load: %.1f%%").printf(host.cpu_pct);
            host_cpu_sparkline.add_value(host.cpu_pct);

            host_ram_row.subtitle = _("Host RAM: %.2f / %.1f GB (%.0f%%)").printf(host.ram_used_gb, host.ram_total_gb, host.ram_pct);
            host_ram_sparkline.add_value(host.ram_pct);

            vm_statuses.foreach((id, status) => {
                VmCard card = cards.lookup(id);
                if (card != null && status != null) {
                    card.update_status(status);
                }
            });
        }

        private void load_window_state() {
            string state_path = ConfigManager.get_state_file();
            int w = 580;
            int h = 740;
            bool max = false;

            if (FileUtils.test(state_path, FileTest.EXISTS)) {
                try {
                    var parser = new Json.Parser();
                    parser.load_from_file(state_path);
                    var root = parser.get_root();
                    if (root != null && root.get_node_type() == Json.NodeType.OBJECT) {
                        unowned Json.Object obj = root.get_object();
                        if (obj.has_member("window")) {
                            unowned Json.Object win_obj = obj.get_object_member("window");
                            if (win_obj.has_member("width")) w = (int)win_obj.get_int_member("width");
                            if (win_obj.has_member("height")) h = (int)win_obj.get_int_member("height");
                            if (win_obj.has_member("maximized")) max = win_obj.get_boolean_member("maximized");
                        }
                    }
                } catch (Error e) {
                    // Ignore
                }
            }

            this.set_default_size(w, h);
            if (max) {
                this.maximize();
            }
        }

        private void save_window_state() {
            string dir = ConfigManager.get_config_dir();
            DirUtils.create_with_parents(dir, 0755);

            var win_obj = new Json.Object();
            win_obj.set_int_member("width", this.get_width());
            win_obj.set_int_member("height", this.get_height());
            win_obj.set_boolean_member("maximized", this.is_maximized());

            var exp_obj = new Json.Object();
            cards.foreach((id, card) => {
                exp_obj.set_boolean_member(id, card.expanded);
            });

            var root_obj = new Json.Object();
            root_obj.set_object_member("window", win_obj);
            root_obj.set_object_member("expanded", exp_obj);

            var root = new Json.Node(Json.NodeType.OBJECT);
            root.set_object(root_obj);

            var generator = new Json.Generator();
            generator.set_root(root);
            generator.set_pretty(true);

            try {
                generator.to_file(ConfigManager.get_state_file());
            } catch (Error e) {
                // Ignore
            }
        }

        private bool on_close_request() {
            monitor.stop();
            save_window_state();
            return false;
        }
    }
}
