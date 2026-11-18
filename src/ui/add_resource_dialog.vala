using GLib.Intl;

/* add_resource_dialog.vala — the single way to add a resource.
 *
 * Page 1 (choose): "Found on this computer" — containers and libvirt VMs from
 *   ResourceDiscovery (scanned automatically, read-only) — and "Set up manually"
 *   (pick a folder and Rigs reads compose.yaml / run-vm.sh, or start from an empty form).
 * Page 2 (ResourceEditorPage): review and edit the settings, then Add. */
namespace Rigs {
    public class AddResourceDialog : Adw.Dialog {
        public signal void resource_added(Resource resource);

        private GenericArray<Resource> existing = new GenericArray<Resource>();
        private Adw.NavigationView navigation;
        private Adw.ToastOverlay toasts;
        private Adw.PreferencesGroup found_group;
        private Gtk.Widget[] found_rows = {};
        private Gtk.Button rescan_btn;
        private bool busy = false;
        private bool dismissed = false;

        public AddResourceDialog(GenericArray<Resource> registered) {
            foreach (var resource in registered.data) existing.add(resource);
            title = _("Add Resource");
            content_width = 560;
            content_height = 640;

            navigation = new Adw.NavigationView();
            toasts = new Adw.ToastOverlay();
            toasts.child = navigation;
            set_child(toasts);
            navigation.add(build_choose_page());
            closed.connect(() => { dismissed = true; });
            scan();
        }

        private Adw.NavigationPage build_choose_page() {
            var toolbar = new Adw.ToolbarView();
            var header = new Adw.HeaderBar();
            rescan_btn = new Gtk.Button.from_icon_name("view-refresh-symbolic");
            rescan_btn.tooltip_text = _("Scan This Computer Again");
            rescan_btn.clicked.connect(scan);
            header.pack_start(rescan_btn);
            toolbar.add_top_bar(header);

            var page = new Adw.PreferencesPage();
            toolbar.content = page;

            found_group = new Adw.PreferencesGroup();
            found_group.title = _("Found on This Computer");
            found_group.description = _("Containers and libvirt virtual machines your user can reach. Scanning changes nothing.");
            page.add(found_group);

            var manual = new Adw.PreferencesGroup();
            manual.title = _("Set Up Manually");
            page.add(manual);
            manual.add(choice_row(_("From a Folder…"),
                _("Rigs reads compose.yaml or run-vm.sh and fills in the settings"), "folder-open-symbolic",
                () => { choose_folder(null); }));
            manual.add(choice_row(_("Compose Project"),
                _("Podman or Docker Compose in a project folder"), "network-server-symbolic",
                () => { choose_folder(ResourceKind.COMPOSE); }));
            manual.add(choice_row(_("QEMU Start Script"),
                _("A folder with run-vm.sh or your own start command"), "computer-symbolic",
                () => { choose_folder(ResourceKind.QEMU); }));

            return new Adw.NavigationPage(toolbar, _("Add Resource"));
        }

        private delegate void Action();

        private Adw.ActionRow choice_row(string title, string subtitle, string icon, owned Action action) {
            var row = new Adw.ActionRow();
            row.title = title;
            row.subtitle = subtitle;
            row.activatable = true;
            row.add_prefix(new Gtk.Image.from_icon_name(icon));
            row.add_suffix(new Gtk.Image.from_icon_name("go-next-symbolic"));
            row.activated.connect(() => { action(); });
            return row;
        }

        private void clear_found() {
            foreach (var row in found_rows) found_group.remove(row);
            found_rows = {};
        }

        private void add_found(Gtk.Widget row) {
            found_group.add(row);
            found_rows += row;
        }

        private void scan() {
            if (busy) return;
            busy = true;
            rescan_btn.sensitive = false;
            clear_found();
            var waiting = new Adw.ActionRow();
            waiting.title = _("Looking for containers and virtual machines…");
            var spinner = new Gtk.Spinner();
            spinner.start();
            waiting.add_suffix(spinner);
            add_found(waiting);
            new Thread<void*>("resource-discovery", () => {
                var found = new ResourceDiscovery().scan(existing);
                Idle.add(() => {
                    if (!dismissed) show_found(found);
                    return Source.REMOVE;
                });
                return null;
            });
        }

        private void show_found(DiscoveryResult found) {
            busy = false;
            rescan_btn.sensitive = true;
            clear_found();
            if (found.candidates.length == 0) {
                var none = new Adw.ActionRow();
                none.title = _("Nothing new found");
                none.subtitle = _("Everything reachable is already added, or a connection below is unavailable.");
                add_found(none);
            }
            foreach (var candidate in found.candidates.data) add_found(candidate_row(candidate));

            // Connection details only matter when something is missing: keep them folded.
            int connected = 0;
            foreach (var source in found.sources.data) if (source.available) connected++;
            var connections = new Adw.ExpanderRow();
            connections.title = _("Connections");
            connections.subtitle = _("%d of %d connected").printf(connected, found.sources.length);
            foreach (var source in found.sources.data) {
                var row = new Adw.ActionRow();
                row.use_markup = false;
                row.title = source.name;
                row.subtitle = source.available ? _("Connected") : source.message;
                row.subtitle_lines = 0;
                row.add_prefix(new Gtk.Image.from_icon_name(source.available ? "emblem-ok-symbolic" : "dialog-information-symbolic"));
                connections.add_row(row);
            }
            add_found(connections);
        }

        private Adw.ActionRow candidate_row(Resource candidate) {
            var row = new Adw.ActionRow();
            row.use_markup = false;
            row.title = candidate.name;
            row.subtitle = candidate.subtitle;
            row.activatable = true;
            row.tooltip_text = _("Review settings before adding");
            row.add_prefix(new Gtk.Image.from_icon_name(candidate.icon));
            var add = new Gtk.Button.with_label(_("Add"));
            add.valign = Gtk.Align.CENTER;
            add.clicked.connect(() => { accept(candidate, row, add); });
            row.add_suffix(add);
            row.activated.connect(() => {
                if (!add.sensitive) return;
                open_editor(candidate, (draft) => {
                    navigation.pop();
                    accept(draft, row, add);
                });
            });
            return row;
        }

        private void accept(Resource resource, Adw.ActionRow row, Gtk.Button button) {
            button.sensitive = false;
            button.label = _("Added");
            row.activatable = false;
            existing.add(resource);
            resource_added(resource);
            toasts.add_toast(new Adw.Toast(_("Added “%s”").printf(resource.name)));
        }

        private delegate void Confirm(Resource draft);

        private void open_editor(Resource draft, owned Confirm confirm) {
            var editor = new ResourceEditorPage(draft);
            editor.confirmed.connect((d) => { confirm(d); });
            navigation.push(editor);
        }

        // kind == null: detect from the folder. Cancelling the folder chooser opens an empty form.
        private void choose_folder(ResourceKind? kind) {
            var dialog = new Gtk.FileDialog();
            dialog.title = _("Choose the Resource Folder");
            dialog.select_folder.begin(get_root() as Gtk.Window, null, (obj, res) => {
                string? path = null;
                try {
                    var folder = dialog.select_folder.end(res);
                    if (folder != null) path = folder.get_path();
                } catch (Error e) {
                    if (kind == null) return; // "From a folder" without a folder means nothing to do.
                }
                Resource draft;
                if (path == null) draft = ResourcePresets.blank((ResourceKind) kind);
                else {
                    draft = ResourcePresets.for_folder(path, default_runtime());
                    if (kind != null && draft.kind != kind) draft = ResourcePresets.blank((ResourceKind) kind, path);
                }
                if (draft.kind == ResourceKind.COMPOSE && path == null) draft.runtime = default_runtime();
                open_editor(draft, (d) => {
                    resource_added(d);
                    close();
                });
            });
        }

        // Podman unless only Docker is installed.
        private static ContainerRuntime default_runtime() {
            if (Environment.find_program_in_path("podman") == null && Environment.find_program_in_path("docker") != null)
                return ContainerRuntime.DOCKER;
            return ContainerRuntime.PODMAN;
        }
    }
}
