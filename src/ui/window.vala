using GLib.Intl;

/* window.vala — the main window: header bar, host overview, resource list and the
 * glue between card buttons and ResourceActions. Widgets live in host_overview.vala,
 * resource_list.vala and resource_card.vala; persisted state in core/window_state.vala. */
namespace Rigs {

    public class Window : Adw.ApplicationWindow {
        private GenericArray<Resource> resources;
        private SystemMonitor monitor;
        private ResourceActions actions = new ResourceActions();
        private WindowState state;
        private uint save_state_source = 0;

        private Adw.ToastOverlay toast_overlay;
        private HostOverview host_overview;
        private ResourceList resource_list;
        private Adw.PreferencesGroup empty_group;
        private Adw.StatusPage empty_status_page;
        private Gtk.SearchBar search_bar;
        private Gtk.SearchEntry search_entry;
        private Gtk.ToggleButton search_toggle_btn;

        public Window(Adw.Application app) {
            Object(application: app);
        }

        construct {
            this.title = "Rigs";
            this.icon_name = "io.github.vovche.Rigs";
            this.resources = ResourceStore.load();
            this.monitor = new SystemMonitor();

            state = WindowState.load(WindowState.default_path());
            this.set_default_size(state.width, state.height);
            if (state.maximized) this.maximize();

            build_ui();
            if (resources.length == 0 && ResourceStore.load_error == null) {
                Idle.add(() => { open_add_dialog(); return Source.REMOVE; });
            }

            this.notify["default-width"].connect(() => { save_window_state(); });
            this.notify["default-height"].connect(() => { save_window_state(); });
            this.notify["maximized"].connect(() => { save_window_state(); });
            this.close_request.connect(on_close_request);

            // Adaptive polling: 1s focused, 3s background, suspended when minimized
            this.notify["is-active"].connect(on_window_state_changed);
            this.notify["suspended"].connect(on_window_state_changed);
            on_window_state_changed();

            monitor.updated.connect((host, statuses) => {
                host_overview.update(host);
                resource_list.update_statuses(statuses);
            });
            monitor.start(resources);
        }

        private void on_window_state_changed() {
            if (this.suspended) {
                monitor.set_interval(MonitorInterval.SUSPENDED);
            } else if (this.is_active) {
                monitor.set_interval(MonitorInterval.FOCUSED);
            } else {
                monitor.set_interval(MonitorInterval.BACKGROUND);
            }
        }

        private void build_ui() {
            var builder = new Gtk.Builder.from_resource("/io/github/vovche/Rigs/shortcuts.ui");
            var overlay = builder.get_object("help_overlay") as Gtk.ShortcutsWindow;
            if (overlay != null) {
                this.set_help_overlay(overlay);
            }

            var search_action = new SimpleAction("search", null);
            search_action.activate.connect(() => {
                search_toggle_btn.active = !search_toggle_btn.active;
                if (search_toggle_btn.active) {
                    search_entry.grab_focus();
                }
            });
            this.add_action(search_action);

            var root = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            this.set_content(root);

            var header = new Adw.HeaderBar();
            var title_widget = new Adw.WindowTitle(_("Rigs"), _("Virtual Machine and Container Hub"));
            header.title_widget = title_widget;

            var add_btn = new Gtk.Button.from_icon_name("list-add-symbolic");
            add_btn.tooltip_text = _("Add Resource (Ctrl+N)");
            add_btn.update_property(Gtk.AccessibleProperty.LABEL, _("Add Resource"));
            add_btn.clicked.connect(open_add_dialog);
            header.pack_start(add_btn);

            var menu = new Menu();
            menu.append(_("Filter Resources"), "win.search");
            menu.append(_("Keyboard Shortcuts"), "win.show-help-overlay");
            menu.append(_("Report an Issue"), "app.report-issue");
            menu.append(_("About Rigs"), "app.about");
            menu.append(_("Quit"), "app.quit");

            var menu_btn = new Gtk.MenuButton();
            menu_btn.icon_name = "open-menu-symbolic";
            menu_btn.tooltip_text = _("Main Menu");
            menu_btn.update_property(Gtk.AccessibleProperty.LABEL, _("Main Menu"));
            menu_btn.menu_model = menu;
            header.pack_end(menu_btn);

            search_toggle_btn = new Gtk.ToggleButton();
            search_toggle_btn.icon_name = "edit-find-symbolic";
            search_toggle_btn.tooltip_text = _("Filter Resources (Ctrl+F)");
            search_toggle_btn.update_property(Gtk.AccessibleProperty.LABEL, _("Filter Resources"));
            header.pack_end(search_toggle_btn);

            root.append(header);

            search_bar = new Gtk.SearchBar();
            search_entry = new Gtk.SearchEntry();
            search_entry.hexpand = true;
            search_entry.placeholder_text = _("Filter added resources by name, type or ports…");
            search_bar.set_child(search_entry);
            search_bar.connect_entry(search_entry);
            search_bar.bind_property("search-mode-enabled", search_toggle_btn, "active", BindingFlags.BIDIRECTIONAL);
            search_entry.search_changed.connect(on_search_changed);
            root.append(search_bar);

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

            host_overview = new HostOverview();
            page.add(host_overview);

            // Empty State
            empty_group = new Adw.PreferencesGroup();
            empty_status_page = new Adw.StatusPage();
            empty_status_page.icon_name = "utilities-system-monitor-symbolic";
            empty_status_page.title = _("No Resources Yet");
            empty_status_page.description = _("Add a virtual machine or container. Rigs also looks for existing ones on this computer.");

            var empty_add_btn = new Gtk.Button.with_label(_("Add Resource"));
            empty_add_btn.add_css_class("suggested-action");
            empty_add_btn.add_css_class("pill");
            empty_add_btn.halign = Gtk.Align.CENTER;
            empty_add_btn.clicked.connect(open_add_dialog);
            empty_status_page.set_child(empty_add_btn);
            empty_group.add(empty_status_page);
            page.add(empty_group);

            resource_list = new ResourceList();
            page.add(resource_list);
            for (int i = 0; i < resources.length; i++) render_card(resources[i]);

            update_empty_state();
        }

        private void render_card(Resource resource) {
            bool expanded;
            bool known = state.expanded.lookup_extended(resource.id, null, out expanded);
            var card = resource_list.add_card(resource, known ? (bool?) expanded : null);

            card.start_requested.connect((r) => { start_resource(r); });
            card.stop_requested.connect((r) => { stop_resource(r); });
            card.connect_requested.connect((r) => { actions.open_console(r); });
            card.remove_requested.connect((r) => { prompt_remove(r); });
            card.insert_iso_requested.connect((r) => { choose_and_insert_iso(r, card); });
            card.eject_iso_requested.connect((r) => { eject_iso(r, card); });
            card.guest_tools_requested.connect((r, guest_state) => {
                var dialog = new GuestToolsDialog(r, guest_state);
                dialog.settings_saved.connect(() => { persist(); monitor.set_resources(resources); });
                dialog.present(this);
            });
            card.issue_details_requested.connect((r, issue) => { new IssueDialog(r, issue).present(this); });
            card.issue_raised.connect((r, issue) => { show_issue(r, issue); });
            card.notify["expanded"].connect(() => { save_window_state(); });
        }

        public void open_add_dialog() {
            if (!configuration_ready()) return;
            var dialog = new AddResourceDialog(resources);
            dialog.resource_added.connect(register_resource);
            dialog.present(this);
        }

        private bool configuration_ready() {
            if (ResourceStore.load_error == null) return true;
            var dialog = new Adw.AlertDialog(_("Configuration Needs Attention"), ResourceStore.load_error);
            dialog.add_response("close", _("Close"));
            dialog.present(this);
            return false;
        }

        private void register_resource(Resource resource) {
            for (int i = 0; i < resources.length; i++) {
                if (resources[i].id == resource.id) return;
            }
            resources.add(resource);
            monitor.set_resources(resources);
            persist();
            render_card(resource);
            update_empty_state();
            save_window_state();
            toast_overlay.add_toast(new Adw.Toast(_("Registered '%s'").printf(resource.name)));
        }

        // SearchTarget (GNOME Shell search provider) entry points.
        public GenericArray<Resource> get_resources() {
            return this.resources;
        }

        public void focus_resource(string id) {
            if (search_bar.search_mode_enabled) {
                search_entry.set_text("");
                search_bar.search_mode_enabled = false;
            }
            resource_list.focus_card(id);
        }

        public void set_search_query(string query) {
            search_bar.search_mode_enabled = true;
            search_entry.set_text(query);
            search_entry.grab_focus();
        }

        private void update_empty_state() {
            bool empty = (resources.length == 0);
            empty_group.visible = empty;
            resource_list.visible = !empty;
            search_toggle_btn.sensitive = !empty;
            if (empty && search_bar.search_mode_enabled) {
                search_bar.search_mode_enabled = false;
            }
        }

        private void on_search_changed() {
            resource_list.filter(search_entry.get_text());
        }

        private void notify_user(string title, string body) {
            var notif = new Notification(title);
            notif.set_body(body);
            notif.set_default_action("app.activate");
            var app = this.application as Adw.Application;
            if (app != null) {
                app.send_notification("rigs-vm-event", notif);
            }
        }

        private void choose_and_insert_iso(Resource resource, ResourceCard card) {
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
                    if (file == null) return;
                    string? iso_path = file.get_path();
                    if (iso_path == null) throw new IOError.NOT_SUPPORTED(_("Only local files can be inserted."));
                    resource.attached_iso = iso_path;
                    persist();
                    card.update_iso_subtitle();
                    actions.insert_iso(resource, iso_path);
                    string message = _("Inserted '%s' into %s").printf(Path.get_basename(iso_path), resource.name);
                    toast_overlay.add_toast(new Adw.Toast(message));
                    notify_user(_("Optical Drive (ISO)"), message);
                } catch (Error e) {
                    if (e.matches(Gtk.DialogError.quark(), Gtk.DialogError.DISMISSED)) return;
                    toast_overlay.add_toast(new Adw.Toast(_("Could not open the disk image: %s").printf(e.message)));
                }
            });
        }

        private void eject_iso(Resource resource, ResourceCard card) {
            resource.attached_iso = "";
            persist();
            card.update_iso_subtitle();
            actions.eject_iso(resource);
            string message = _("Ejected optical media from %s").printf(resource.name);
            toast_overlay.add_toast(new Adw.Toast(message));
            notify_user(_("Optical Drive (ISO)"), message);
        }

        private void start_resource(Resource resource) {
            toast_overlay.add_toast(new Adw.Toast(_("Starting %s…").printf(resource.name)));
            notify_user(_("Starting %s…").printf(resource.name), _("Virtual machine initialization requested"));
            actions.start(resource);
        }

        private void stop_resource(Resource resource) {
            toast_overlay.add_toast(new Adw.Toast(_("Stopping %s…").printf(resource.name)));
            notify_user(_("Stopping %s…").printf(resource.name), _("Virtual machine shutdown requested"));
            actions.stop(resource);
        }

        // Every configuration write goes through here so a failed save is never silent.
        private void persist() {
            if (ResourceStore.save(resources)) return;
            var toast = new Adw.Toast(_("Could not save changes: %s").printf(ResourceStore.save_error ?? ""));
            toast.priority = Adw.ToastPriority.HIGH;
            toast_overlay.add_toast(toast);
        }

        private void show_issue(Resource resource, ResourceIssue issue) {
            var toast = new Adw.Toast("%s: %s".printf(ResourceIssue.headline(issue.operation, resource.name), issue.title));
            toast.button_label = _("Details");
            // Keep the default timeout: a persistent toast would block the overlay queue.
            // The card's warning icon keeps the details reachable.
            toast.button_clicked.connect(() => { new IssueDialog(resource, issue).present(this); });
            toast_overlay.add_toast(toast);
        }

        private void prompt_remove(Resource resource) {
            var dialog = new Adw.AlertDialog(
                _("Remove '%s'?").printf(resource.name),
                _("The virtual machine will be removed from Rigs. Your files and VM disk on the host will remain untouched.")
            );
            dialog.add_response("cancel", _("Cancel"));
            dialog.add_response("remove", _("Remove"));
            dialog.set_response_appearance("remove", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.set_default_response("cancel");
            dialog.set_close_response("cancel");
            dialog.response.connect((d, resp) => {
                if (resp == "remove") execute_remove(resource);
            });
            dialog.present(this);
        }

        private void execute_remove(Resource resource) {
            int idx = -1;
            for (int i = 0; i < resources.length; i++) {
                if (resources[i].id == resource.id) {
                    idx = i;
                    break;
                }
            }
            if (idx < 0) return;

            Resource removed = resources[idx];
            resources.remove_index(idx);
            monitor.set_resources(resources);
            persist();
            resource_list.remove_card(removed.id);
            update_empty_state();
            save_window_state();

            var toast = new Adw.Toast(_("Removed '%s'").printf(removed.name));
            toast.button_label = _("Undo");
            toast.button_clicked.connect(() => {
                for (int i = 0; i < resources.length; i++) {
                    if (resources[i].id == removed.id) return;
                }
                int restore_index = idx < (int)resources.length ? idx : (int)resources.length;
                resources.insert(restore_index, removed);
                monitor.set_resources(resources);
                persist();
                render_card(removed);
                resource_list.reorder(resources);
                update_empty_state();
                save_window_state();
            });
            toast_overlay.add_toast(toast);
        }

        // Debounced: size notifications fire for every pixel of a resize drag.
        private void save_window_state() {
            if (save_state_source != 0) return;
            save_state_source = Timeout.add(500, () => {
                save_state_source = 0;
                write_window_state();
                return Source.REMOVE;
            });
        }

        private void write_window_state() {
            // default-width/height hold the unmaximized size; get_width() would store the maximized one.
            state.width = this.default_width;
            state.height = this.default_height;
            state.maximized = this.is_maximized();
            resource_list.collect_expanded(state.expanded);
            try {
                state.save(WindowState.default_path());
            } catch (Error e) {
                // Window geometry is a convenience; resources are saved separately (persist()).
            }
        }

        private bool on_close_request() {
            monitor.stop();
            if (save_state_source != 0) {
                Source.remove(save_state_source);
                save_state_source = 0;
            }
            write_window_state();
            return false;
        }
    }
}
