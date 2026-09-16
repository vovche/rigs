/* application.vala — Application lifecycle and global actions for Rigs */

using GLib.Intl;

namespace Rigs {

    public class Application : Adw.Application {
        public const string APP_ID = "io.github.vovche.Rigs";

        public Application() {
            Object(
                application_id: APP_ID,
                flags: ApplicationFlags.FLAGS_NONE
            );
        }

        protected override void activate() {
            base.activate();

            // Load CSS
            var provider = new Gtk.CssProvider();
            provider.load_from_resource("/io/github/vovche/Rigs/style.css");
            Gtk.StyleContext.add_provider_for_display(
                Gdk.Display.get_default(),
                provider,
                Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
            );

            setup_actions();

            var win = this.active_window as Window;
            if (win == null) {
                win = new Window(this);
            }
            win.present();
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
                var win = this.active_window as Window;
                if (win != null) {
                    win.open_add_dialog();
                }
            });
            this.add_action(add_action);

            this.set_accels_for_action("app.about", { "F1" });
            this.set_accels_for_action("app.add-vm", { "<Control>n" });
            this.set_accels_for_action("app.quit", { "<Control>q", "<Control>w" });
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
            about.version = "1.0.0";
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
