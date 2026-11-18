using GLib.Intl;

namespace Rigs {
    public class DiscoveryDialog : Adw.Dialog {
        public signal void resource_added(Resource resource);
        private GenericArray<Resource> existing = new GenericArray<Resource>();
        private Adw.PreferencesGroup sources;
        private Adw.PreferencesGroup resources;
        private Gtk.Box results;
        private Gtk.Button scan_button;
        private Gtk.Spinner spinner;
        private bool busy = false;
        private bool dismissed = false;

        public DiscoveryDialog(GenericArray<Resource> registered) {
            foreach (var resource in registered.data) existing.add(resource);
            title = _("Find Resources");
            content_width = 600;
            content_height = 620;
            var root = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            set_child(root);
            var header = new Adw.HeaderBar();
            root.append(header);
            scan_button = new Gtk.Button.with_label(_("Scan Again"));
            scan_button.clicked.connect(scan);
            header.pack_start(scan_button);
            spinner = new Gtk.Spinner();
            header.pack_end(spinner);
            var scrolled = new Gtk.ScrolledWindow();
            scrolled.vexpand = true;
            root.append(scrolled);
            results = new Gtk.Box(Gtk.Orientation.VERTICAL, 24);
            results.margin_start = results.margin_end = 18;
            results.margin_top = results.margin_bottom = 18;
            scrolled.set_child(results);
            closed.connect(() => { dismissed = true; });
            scan();
        }

        private void scan() {
            if (busy) return;
            busy = true;
            scan_button.sensitive = false;
            spinner.start();
            while (results.get_first_child() != null) results.remove(results.get_first_child());
            var message = new Gtk.Label(_("Looking for containers and virtual machines…"));
            message.wrap = true;
            results.append(message);
            new Thread<void*>("resource-discovery", () => {
                var found = new ResourceDiscovery().scan(existing);
                Idle.add(() => {
                    if (!dismissed) show_results(found);
                    return Source.REMOVE;
                });
                return null;
            });
        }

        private void show_results(DiscoveryResult found) {
            busy = false;
            scan_button.sensitive = true;
            spinner.stop();
            while (results.get_first_child() != null) results.remove(results.get_first_child());
            sources = new Adw.PreferencesGroup();
            sources.title = _("Connections");
            sources.description = _("Only resources accessible to your current user are listed. Scanning does not change them.");
            results.append(sources);
            foreach (var source in found.sources.data) {
                var row = new Adw.ActionRow();
                row.use_markup = false;
                row.title = source.name;
                row.subtitle = source.available ? _("Connected") : source.message;
                row.subtitle_lines = 0;
                row.add_prefix(new Gtk.Image.from_icon_name(source.available ? "emblem-ok-symbolic" : "dialog-information-symbolic"));
                sources.add(row);
            }
            resources = new Adw.PreferencesGroup();
            resources.title = _("Available Resources");
            resources.description = found.candidates.length == 0
                ? _("No new resources found. Check the connections above or add a machine manually.")
                : _("Choose which resources to add to Rigs. Existing machines and containers keep their current settings.");
            results.append(resources);
            foreach (var resource in found.candidates.data) {
                var row = new Adw.ActionRow();
                row.use_markup = false;
                row.title = resource.name;
                row.subtitle = resource.subtitle;
                row.add_prefix(new Gtk.Image.from_icon_name(resource.icon));
                var add = new Gtk.Button.with_label(_("Add"));
                add.valign = Gtk.Align.CENTER;
                add.clicked.connect(() => {
                    add.sensitive = false;
                    add.label = _("Added");
                    existing.add(resource);
                    resource_added(resource);
                });
                row.add_suffix(add);
                resources.add(row);
            }
        }
    }
}
