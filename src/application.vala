/* application.vala — Application lifecycle and global actions for Rigs */

using GLib.Intl;

namespace Rigs {

    public class Application : Adw.Application, SearchTarget {
        public const string APP_ID = "io.github.vovche.Rigs";

        private SearchProvider search_provider;
        private uint search_provider_id = 0;

        public Application() {
            Object(
                application_id: APP_ID,
                flags: ApplicationFlags.FLAGS_NONE
            );
        }

        // The single main window, even while a secondary window (shortcuts) is active.
        // Do not cast active_window: it is null whenever another window (shortcuts) has focus.
        public Window? main_window() {
            foreach (var w in get_windows()) {
                var main = w as Window;
                if (main != null) return main;
            }
            return null;
        }

        public Window ensure_main_window() {
            return main_window() ?? new Window(this);
        }

        // SearchTarget: keep the D-Bus service alive while GNOME Shell is querying.
        public void begin_query() { this.hold(); }
        public void end_query() { this.release(); }

        public GenericArray<VmModel> get_vms() {
            var win = main_window();
            if (win != null) {
                return win.get_vms();
            }
            return ConfigManager.load_vms();
        }

        public void focus_vm(string id) {
            var win = ensure_main_window();
            win.present();
            win.focus_vm(id);
        }

        public void set_search_query(string query) {
            var win = ensure_main_window();
            win.present();
            win.set_search_query(query);
        }

        protected override void startup() {
            base.startup();

            // Load CSS
            var provider = new Gtk.CssProvider();
            provider.load_from_resource("/io/github/vovche/Rigs/style.css");
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );

            setup_actions();
            this.set_inactivity_timeout(10000);
        }

        protected override bool dbus_register(DBusConnection connection, string object_path) throws GLib.Error {
            if (!base.dbus_register(connection, object_path)) {
                return false;
            }

            if (search_provider == null) {
                search_provider = new SearchProvider(this);
            }

            try {
                search_provider_id = connection.register_object(
                    "/io/github/vovche/Rigs/SearchProvider",
                    search_provider
                );
            } catch (IOError e) {
                warning("Failed to register GNOME Shell Search Provider on D-Bus: %s", e.message);
            }

            return true;
        }

        protected override void dbus_unregister(DBusConnection connection, string object_path) {
            if (search_provider_id != 0) {
                connection.unregister_object(search_provider_id);
                search_provider_id = 0;
            }
            base.dbus_unregister(connection, object_path);
        }

        protected override void activate() {
            base.activate();

            ensure_main_window().present();
        }

        private void setup_actions() {
            var about_action = new SimpleAction("about", null);
            about_action.activate.connect(show_about);
            this.add_action(about_action);

            var report_action = new SimpleAction("report-issue", null);
            report_action.activate.connect(open_report_issue);
            this.add_action(report_action);

            var quit_action = new SimpleAction("quit", null);
            quit_action.activate.connect(() => { this.quit(); });
            this.add_action(quit_action);

            var add_action = new SimpleAction("add-vm", null);
            add_action.activate.connect(() => {
                var win = main_window();
                if (win != null) {
                    win.open_add_dialog();
                }
            });
            this.add_action(add_action);

            this.set_accels_for_action("app.about", { "F1" });
            this.set_accels_for_action("app.add-vm", { "<Control>n" });
            this.set_accels_for_action("app.quit", { "<Control>q", "<Control>w" });
            this.set_accels_for_action("win.search", { "<Control>f" });
            this.set_accels_for_action("win.show-help-overlay", { "<Control>question" });
        }

        private void open_report_issue() {
            var launcher = new Gtk.UriLauncher("https://github.com/vovche/rigs/issues/new/choose");
            launcher.launch.begin(this.active_window, null);
        }

        private void show_about() {
            var about = new Adw.AboutDialog();
            about.application_name = "Rigs";
            about.application_icon = "io.github.vovche.Rigs";
            about.developer_name = "vovche";
            about.version = Config.VERSION;
            about.comments = _("Ultra-fast, native GNOME Virtual Machine and Container Hub written in Vala.");
            about.website = "https://github.com/vovche/rigs";
            about.issue_url = "https://github.com/vovche/rigs/issues/new/choose";
            about.license_type = Gtk.License.APACHE_2_0;
            about.debug_info = SystemDiagnostics.get_report();
            about.debug_info_filename = "rigs-diagnostics.txt";

            about.present(this.active_window);
        }
    }
}
