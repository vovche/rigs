using GLib.Intl;

/* resource_editor_page.vala — the settings form for a new resource (second page of
 * AddResourceDialog). Edits a draft Resource in place; "Add" is enabled only while
 * ResourcePresets.validate(draft) is null, and the reason is shown otherwise. */
namespace Rigs {
    public class ResourceEditorPage : Adw.NavigationPage {
        public signal void confirmed(Resource draft);

        public Resource draft { get; construct; }

        private Gtk.Button add_btn;
        private Gtk.Label problem;
        private Adw.ComboRow kind_row;
        private Adw.ComboRow runtime_row;
        private Adw.ActionRow identity_row;
        private Adw.EntryRow name_row;
        private Adw.EntryRow subtitle_row;
        private Adw.EntryRow details_row;
        private Adw.EntryRow dir_row;
        private Adw.EntryRow start_row;
        private Adw.EntryRow stop_row;
        private Adw.EntryRow connect_row;
        private Adw.EntryRow container_row;
        private Adw.EntryRow process_row;
        private Adw.EntryRow monitor_row;
        private Adw.EntryRow qmp_row;
        private Adw.EntryRow agent_row;
        private Adw.PreferencesGroup location_group;
        private Adw.PreferencesGroup commands_group;
        private Adw.PreferencesGroup status_group;
        private bool loading = false;

        // Manual drafts may switch between COMPOSE and QEMU; discovered ones keep their kind.
        private static ResourceKind[] EDITABLE_KINDS = { ResourceKind.COMPOSE, ResourceKind.QEMU };

        public ResourceEditorPage(Resource draft) {
            Object(draft: draft, title: _("Resource Settings"));
        }

        construct {
            var toolbar = new Adw.ToolbarView();
            var header = new Adw.HeaderBar();
            add_btn = new Gtk.Button.with_label(_("Add"));
            add_btn.add_css_class("suggested-action");
            add_btn.clicked.connect(() => { collect(); if (ResourcePresets.validate(draft) == null) confirmed(draft); });
            header.pack_end(add_btn);
            toolbar.add_top_bar(header);

            var page = new Adw.PreferencesPage();
            toolbar.content = page;
            this.child = toolbar;

            var general = new Adw.PreferencesGroup();
            general.title = _("General");
            page.add(general);
            name_row = entry(general, _("Name"));
            subtitle_row = entry(general, _("Subtitle / OS"));
            details_row = entry(general, _("Ports and Services"));

            kind_row = new Adw.ComboRow();
            kind_row.title = _("Type");
            kind_row.model = new Gtk.StringList({ _("Compose project"), _("QEMU script") });
            general.add(kind_row);
            identity_row = new Adw.ActionRow();
            identity_row.title = _("Type");
            identity_row.subtitle_selectable = true;
            general.add(identity_row);

            location_group = new Adw.PreferencesGroup();
            location_group.title = _("Location");
            page.add(location_group);
            dir_row = entry(location_group, _("Folder"));
            var browse = new Gtk.Button.from_icon_name("folder-open-symbolic");
            browse.add_css_class("flat");
            browse.valign = Gtk.Align.CENTER;
            browse.tooltip_text = _("Choose Folder and Read Its Settings");
            browse.clicked.connect(choose_folder);
            dir_row.add_suffix(browse);
            runtime_row = new Adw.ComboRow();
            runtime_row.title = _("Container Engine");
            runtime_row.model = new Gtk.StringList({ "Podman", "Docker" });
            location_group.add(runtime_row);

            commands_group = new Adw.PreferencesGroup();
            commands_group.title = _("Commands");
            page.add(commands_group);
            start_row = entry(commands_group, _("Start Command"));
            stop_row = entry(commands_group, _("Stop Command"));
            connect_row = entry(commands_group, _("Connect Command"));

            status_group = new Adw.PreferencesGroup();
            status_group.title = _("Status and Control");
            page.add(status_group);
            container_row = entry(status_group, _("Container Name"));
            process_row = entry(status_group, _("Process Match"));
            monitor_row = entry(status_group, _("QEMU Monitor Socket"));
            qmp_row = entry(status_group, _("QMP Socket"));
            agent_row = entry(status_group, _("Guest Agent Socket"));

            var problem_group = new Adw.PreferencesGroup();
            problem = new Gtk.Label("");
            problem.wrap = true;
            problem.xalign = 0;
            problem.add_css_class("error");
            problem_group.add(problem);
            page.add(problem_group);

            load();
            kind_row.notify["selected"].connect(() => {
                if (loading) return;
                collect();
                draft.kind = EDITABLE_KINDS[kind_row.selected];
                draft.icon = ResourcePresets.icon_for(draft.kind);
                refresh();
            });
            runtime_row.notify["selected"].connect(() => { if (!loading) { collect(); refresh(); } });
        }

        private Adw.EntryRow entry(Adw.PreferencesGroup group, string title) {
            var row = new Adw.EntryRow();
            row.title = title;
            row.changed.connect(() => { if (!loading) { collect(); validate(); } });
            group.add(row);
            return row;
        }

        // draft → widgets
        private void load() {
            loading = true;
            name_row.text = draft.name;
            subtitle_row.text = draft.subtitle;
            details_row.text = draft.details;
            dir_row.text = draft.dir;
            start_row.text = draft.start_cmd;
            stop_row.text = draft.stop_cmd;
            connect_row.text = draft.connect_cmd;
            container_row.text = draft.container_name;
            process_row.text = draft.process_match;
            monitor_row.text = draft.monitor_socket;
            qmp_row.text = draft.qmp_socket;
            agent_row.text = draft.guest_agent_socket;
            kind_row.selected = draft.kind == ResourceKind.QEMU ? 1 : 0;
            runtime_row.selected = draft.runtime == ContainerRuntime.DOCKER ? 1 : 0;
            loading = false;
            refresh();
        }

        // widgets → draft
        private void collect() {
            draft.name = name_row.text.strip();
            draft.subtitle = subtitle_row.text.strip();
            draft.details = details_row.text.strip();
            draft.dir = dir_row.text.strip();
            draft.start_cmd = start_row.text.strip();
            draft.stop_cmd = stop_row.text.strip();
            draft.connect_cmd = connect_row.text.strip();
            draft.container_name = container_row.text.strip();
            draft.process_match = process_row.text.strip();
            draft.monitor_socket = monitor_row.text.strip();
            draft.qmp_socket = qmp_row.text.strip();
            draft.guest_agent_socket = agent_row.text.strip();
            if (draft.kind == ResourceKind.COMPOSE)
                draft.runtime = runtime_row.selected == 1 ? ContainerRuntime.DOCKER : ContainerRuntime.PODMAN;
        }

        // Shows only the fields that matter for the kind, with what an empty field means.
        private void refresh() {
            bool compose = draft.kind == ResourceKind.COMPOSE;
            bool qemu = draft.kind == ResourceKind.QEMU;
            bool editable = compose || qemu;
            kind_row.visible = editable;
            identity_row.visible = !editable;
            if (draft.kind == ResourceKind.CONTAINER)
                identity_row.subtitle = "%s • %s".printf(draft.runtime.command(), draft.resource_id);
            else if (draft.kind == ResourceKind.LIBVIRT)
                identity_row.subtitle = "libvirt • %s • %s".printf(draft.connection_uri, draft.resource_id);
            identity_row.title = draft.kind == ResourceKind.LIBVIRT ? _("libvirt Domain") : _("Container");

            location_group.visible = editable;
            runtime_row.visible = compose;
            start_row.visible = stop_row.visible = editable;
            commands_group.description = compose
                ? _("Empty Start and Stop run “%s compose up -d” and “%s compose down” in the folder.").printf(draft.runtime.command(), draft.runtime.command())
                : qemu ? _("Empty Start runs ./run-vm.sh. Empty Stop shuts the VM down through the monitor socket.")
                : _("Start and stop use the engine directly. Connect runs your command, e.g. a remote desktop client.");
            if (draft.kind == ResourceKind.LIBVIRT) commands_group.visible = false;

            status_group.visible = compose || qemu;
            container_row.visible = compose;
            process_row.visible = monitor_row.visible = qemu;
            qmp_row.visible = agent_row.visible = qemu;
            status_group.description = compose
                ? _("Rigs reads status and errors from this container. Without it, a failed start cannot be detected.")
                : _("Process Match is part of the QEMU command line used to find the running VM, e.g. its -name.");
            validate();
        }

        private void validate() {
            string? reason = ResourcePresets.validate(draft);
            add_btn.sensitive = reason == null;
            problem.label = reason ?? "";
            problem.visible = reason != null;
        }

        // Re-reads the folder; fields the user already typed are kept.
        private void choose_folder() {
            var dialog = new Gtk.FileDialog();
            dialog.title = _("Choose the Resource Folder");
            if (FileUtils.test(dir_row.text.strip(), FileTest.IS_DIR)) dialog.initial_folder = File.new_for_path(dir_row.text.strip());
            dialog.select_folder.begin(get_root() as Gtk.Window, null, (obj, res) => {
                try {
                    var folder = dialog.select_folder.end(res);
                    string? path = folder != null ? folder.get_path() : null;
                    if (path == null) return;
                    collect();
                    var found = ResourcePresets.for_folder(path, draft.runtime);
                    if (draft.kind == ResourceKind.QEMU && found.kind != ResourceKind.QEMU) found = ResourcePresets.blank(ResourceKind.QEMU, path);
                    merge_from(found);
                    load();
                } catch (Error e) {
                    // Dismissed.
                }
            });
        }

        private void merge_from(Resource found) {
            draft.dir = found.dir;
            draft.kind = found.kind;
            draft.icon = found.icon;
            if (draft.name.length == 0) draft.name = found.name;
            if (draft.subtitle.length == 0) draft.subtitle = found.subtitle;
            if (draft.details.length == 0) draft.details = found.details;
            if (draft.start_cmd.length == 0) draft.start_cmd = found.start_cmd;
            if (draft.connect_cmd.length == 0) draft.connect_cmd = found.connect_cmd;
            if (draft.container_name.length == 0) draft.container_name = found.container_name;
            if (draft.process_match.length == 0) draft.process_match = found.process_match;
            if (draft.monitor_socket.length == 0) draft.monitor_socket = found.monitor_socket;
            if (draft.qmp_socket.length == 0) draft.qmp_socket = found.qmp_socket;
            if (draft.guest_agent_socket.length == 0) draft.guest_agent_socket = found.guest_agent_socket;
            if (draft.guest_os.length == 0) draft.guest_os = found.guest_os;
        }
    }
}
