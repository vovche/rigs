using GLib.Intl;

namespace Rigs {
    public class GuestDriverSetupDialog : Adw.Dialog {
        private delegate void Work() throws Error;
        private VmModel vm;
        private WindowsGuestInstaller installer = new WindowsGuestInstaller();
        private GuestToolsPackages packages = new GuestToolsPackages();
        private GuestMedia media = new GuestMedia();
        private GuestToolsProbe? probe;
        private GuestToolsArtifact? artifact;
        private GenericArray<GuestOpticalDrive> empty_drives = new GenericArray<GuestOpticalDrive>();
        private bool busy = false;
        private bool pending = false;
        private bool dismissed = false;
        private bool reboot_required = false;
        private Cancellable? download_cancel;
        private Gtk.Label status;
        private Gtk.Label package_label;
        private Gtk.Label result_label;
        private Gtk.Label logs_label;
        private Gtk.Label media_label;
        private Gtk.Button prepare;
        private Gtk.Button local_installer;
        private Gtk.Button install;
        private Gtk.Button resume;
        private Gtk.Button restart;
        private Gtk.Button open_journal;
        private Gtk.Button download_iso;
        private Gtk.Button local_iso;
        private Gtk.Button cancel;
        private Adw.ComboRow drive;
        private string journal_path = "";

        private static Gtk.Label text(string value) {
            var label = new Gtk.Label(value);
            label.wrap = true;
            label.xalign = 0;
            label.selectable = true;
            label.margin_top = 6;
            label.margin_bottom = 6;
            return label;
        }

        private Gtk.Button button(Adw.PreferencesGroup group, string label) {
            var result = new Gtk.Button.with_label(label);
            result.margin_top = 6;
            group.add(result);
            return result;
        }

        public GuestDriverSetupDialog(VmModel source) {
            // Keep a private model snapshot throughout asynchronous jobs.
            var node = new Json.Node(Json.NodeType.OBJECT);
            node.set_object(source.to_json_object());
            vm = VmModel.from_json_node(node);
            title = _("Windows Guest Drivers");
            content_width = 620;
            content_height = 720;
            var root = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            set_child(root);
            root.append(new Adw.HeaderBar());
            var scroll = new Gtk.ScrolledWindow();
            scroll.vexpand = true;
            root.append(scroll);
            var page = new Adw.PreferencesPage();
            scroll.set_child(page);
            var connection = new Adw.PreferencesGroup();
            connection.title = _("Guest Connection");
            page.add(connection);
            connection.add(text(vm.name));
            status = text(_("Checking the guest agent, Windows and CD drives…"));
            connection.add(status);
            connection.add(text(_("Automatic setup requires a running Windows guest agent and administrator access. Missing statistics alone do not prove that drivers are missing.")));

            var setup = new Adw.PreferencesGroup();
            setup.title = _("Verified Driver Installer");
            setup.description = _("The official pinned package is checked by SHA256. Windows must also verify its Red Hat digital signature before installation.");
            page.add(setup);
            package_label = text(_("No installer prepared."));
            setup.add(package_label);
            prepare = button(setup, _("Prepare Installer"));
            local_installer = button(setup, _("Choose Local Installer"));
            install = button(setup, _("Install Drivers"));
            install.add_css_class("suggested-action");
            resume = button(setup, _("Check Installation Result"));
            cancel = button(setup, _("Cancel Download"));
            result_label = text("");
            setup.add(result_label);
            logs_label = text("");
            setup.add(logs_label);
            open_journal = button(setup, _("Open Installation Journal"));
            restart = button(setup, _("Restart Windows"));

            var bootstrap = new Adw.PreferencesGroup();
            bootstrap.title = _("Set Up Through the Windows Console");
            bootstrap.description = _("If the guest agent is unavailable, one manual installation step is needed. The VM also needs a virtio-serial channel named org.qemu.guest_agent.0 connected to its dedicated guest-agent socket; configure it in your VM manager and restart the VM if necessary.");
            page.add(bootstrap);
            media_label = text(_("Checking for an empty CD drive…"));
            bootstrap.add(media_label);
            drive = new Adw.ComboRow();
            drive.title = _("Empty CD Drive");
            drive.use_markup = false;
            bootstrap.add(drive);
            download_iso = button(bootstrap, _("Download and Attach VirtIO ISO"));
            local_iso = button(bootstrap, _("Choose Local ISO"));
            bootstrap.add(text(_("After attachment, open the Windows console, open the CD drive and run virtio-win-guest-tools.exe as administrator. Keep the Balloon driver and QEMU Guest Agent selected. Rigs never replaces media in an occupied drive.")));

            prepare.clicked.connect(() => fetch_installer());
            local_installer.clicked.connect(() => choose_file(false));
            install.clicked.connect(confirm_install);
            resume.clicked.connect(() => run(() => { var result = installer.resume(vm); Idle.add(() => { if (!dismissed) show_result(result); return Source.REMOVE; }); }, true));
            restart.clicked.connect(confirm_restart);
            download_iso.clicked.connect(() => attach_iso(null));
            local_iso.clicked.connect(() => choose_file(true));
            cancel.clicked.connect(() => { if (download_cancel != null) download_cancel.cancel(); });
            open_journal.clicked.connect(() => {
                if (journal_path.length > 0)
                    new Gtk.FileLauncher(File.new_for_path(journal_path)).launch.begin(get_root() as Gtk.Window, null);
            });
            installer.progress.connect((message) => Idle.add(() => { if (!dismissed) result_label.label = message; return Source.REMOVE; }));
            packages.progress.connect((received, total) => Idle.add(() => {
                if (!dismissed && download_cancel != null)
                    result_label.label = total > 0 ? _("Downloaded %s of %s").printf(format_size((uint64)received), format_size((uint64)total)) : _("Downloaded %s").printf(format_size((uint64)received));
                return Source.REMOVE;
            }));
            closed.connect(() => {
                dismissed = true;
                if (download_cancel != null) download_cancel.cancel();
            });
            refresh();
            initial_check();
        }

        private void refresh() {
            prepare.sensitive = local_installer.sensitive = !busy;
            install.sensitive = !busy && !pending && artifact != null && probe != null && probe.available && probe.compatible && probe.administrator;
            resume.visible = pending;
            resume.sensitive = !busy;
            restart.visible = reboot_required;
            restart.sensitive = !busy && !pending;
            open_journal.visible = journal_path.length > 0;
            open_journal.sensitive = !busy;
            drive.visible = empty_drives.length > 0;
            drive.sensitive = !busy;
            download_iso.sensitive = local_iso.sensitive = !busy && !pending && empty_drives.length > 0;
            cancel.visible = download_cancel != null;
            cancel.sensitive = busy;
        }

        private void run(owned Work work, bool lock_close = false) {
            if (busy || dismissed) return;
            busy = true;
            can_close = !lock_close;
            refresh();
            new Thread<void*>("guest-driver-setup", () => {
                string? failure = null;
                try { work(); } catch (Error e) { failure = e.message; }
                bool has_pending = installer.has_pending(vm);
                Idle.add(() => {
                    if (!dismissed) {
                        pending = has_pending;
                        busy = false;
                        download_cancel = null;
                        can_close = true;
                        if (failure != null) result_label.label = _("Operation could not be completed: %s").printf(failure);
                        else if (pending && result_label.label.length == 0)
                            result_label.label = _("An earlier installation has no verified outcome yet. Check its result before starting another installation.");
                        refresh();
                    }
                    return Source.REMOVE;
                });
                return null;
            });
        }

        private void initial_check() {
            run(() => {
                GuestToolsProbe? checked = null;
                string connection_error = "";
                try { checked = installer.probe(vm); } catch (Error e) { connection_error = e.message; }
                GenericArray<GuestOpticalDrive>? found = null;
                string media_error = "";
                try { found = media.list_drives(vm); } catch (Error e) { media_error = e.message; }
                Idle.add(() => {
                    if (dismissed) return Source.REMOVE;
                    probe = checked;
                    if (checked != null) {
                        status.label = checked.summary + "\n" + _("Architecture: %s · Version: %s").printf(checked.architecture, checked.version) + "\n" +
                            (checked.balloon_service_running ? _("BalloonService is running.") : _("BalloonService was not confirmed running."));
                    } else status.label = _("Guest agent check failed: %s\nUse the ISO setup below, then check the guest-agent channel and reopen this dialog.").printf(connection_error);
                    var names = new Gtk.StringList(null);
                    uint occupied = 0;
                    if (found != null) {
                        for (int i = 0; i < found.length; i++) {
                            var candidate = found[i];
                            if (candidate.current_iso.length == 0) { empty_drives.add(candidate); names.append(candidate.id); }
                            else occupied++;
                        }
                    }
                    drive.model = names;
                    media_label.label = found == null ? _("CD drives could not be checked: %s").printf(media_error) :
                        _("Empty CD drives: %u · Occupied CD drives: %u").printf(empty_drives.length, occupied);
                    if (empty_drives.length == 0) media_label.label += "\n" + _("Add an empty CD drive in your VM manager to use ISO setup.");
                    refresh();
                    return Source.REMOVE;
                });
            });
        }

        private void show_artifact(GuestToolsArtifact ready) {
            artifact = ready;
            package_label.label = _("Package: %s\nSHA256: %s\nFile: %s").printf(ready.version, ready.sha256, ready.path);
        }

        private void fetch_installer() {
            if (busy) return;
            download_cancel = new Cancellable();
            var cancellation = download_cancel;
            run(() => { var ready = packages.fetch(false, cancellation); Idle.add(() => { if (!dismissed) show_artifact(ready); return Source.REMOVE; }); });
        }

        private void show_result(GuestInstallResult result) {
            result_label.label = result.summary;
            journal_path = result.journal_path;
            logs_label.label = _("Host journal: %s\nWindows installation logs: %s").printf(result.journal_path, result.remote_directory);
            reboot_required = result.state == GuestInstallState.REBOOT_REQUIRED;
        }

        private void confirm_install() {
            if (busy || artifact == null || pending) return;
            var selected = artifact;
            busy = true;
            refresh();
            var confirmation = new Adw.AlertDialog(_("Install Windows Drivers?"),
                _("Install %s (%s) on %s? Windows will verify the Red Hat signature, then install drivers with administrator privileges. Windows will not be forcibly restarted.").printf(Path.get_basename(selected.path), selected.version, vm.name));
            confirmation.add_response("cancel", _("Cancel"));
            confirmation.add_response("install", _("Install Drivers"));
            confirmation.set_response_appearance("install", Adw.ResponseAppearance.SUGGESTED);
            confirmation.set_default_response("cancel");
            confirmation.set_close_response("cancel");
            confirmation.response.connect((dialog, response) => {
                busy = false;
                if (!dismissed && response == "install") run(() => { var result = installer.install(vm, selected); Idle.add(() => { if (!dismissed) show_result(result); return Source.REMOVE; }); }, true);
                else if (!dismissed) refresh();
            });
            confirmation.present(this);
        }

        private void confirm_restart() {
            if (busy || pending || !reboot_required) return;
            busy = true;
            refresh();
            var confirmation = new Adw.AlertDialog(_("Restart Windows?"), _("Restart %s to finish driver setup? Save all work in Windows first; unsaved changes may be lost.").printf(vm.name));
            confirmation.add_response("cancel", _("Cancel"));
            confirmation.add_response("restart", _("Restart Windows"));
            confirmation.set_response_appearance("restart", Adw.ResponseAppearance.DESTRUCTIVE);
            confirmation.set_default_response("cancel");
            confirmation.set_close_response("cancel");
            confirmation.response.connect((dialog, response) => {
                busy = false;
                if (!dismissed && response == "restart") run(() => {
                    installer.reboot(vm);
                    Idle.add(() => { if (!dismissed) { reboot_required = false; result_label.label = _("Restart requested. Reopen guest integration after Windows starts to verify statistics."); } return Source.REMOVE; });
                }, true);
                else if (!dismissed) refresh();
            });
            confirmation.present(this);
        }

        private void choose_file(bool iso) {
            if (busy) return;
            busy = true;
            refresh();
            var chooser = new Gtk.FileDialog();
            chooser.title = iso ? _("Choose VirtIO ISO") : _("Choose VirtIO Windows Installer");
            var filter = new Gtk.FileFilter();
            filter.name = iso ? _("ISO Images") : _("Windows Installers");
            filter.add_pattern(iso ? "*.iso" : "*.exe");
            filter.add_pattern(iso ? "*.ISO" : "*.EXE");
            var filters = new ListStore(typeof(Gtk.FileFilter));
            filters.append(filter);
            chooser.filters = filters;
            chooser.default_filter = filter;
            chooser.open.begin(get_root() as Gtk.Window, null, (obj, response) => {
                busy = false;
                if (dismissed) return;
                try {
                    var selected = chooser.open.end(response);
                    string? path = selected.get_path();
                    if (path == null) result_label.label = _("Choose a local file with an accessible filesystem path.");
                    else if (iso) attach_iso(path);
                    else run(() => { var ready = GuestToolsPackages.local_file(path, false); Idle.add(() => { if (!dismissed) show_artifact(ready); return Source.REMOVE; }); });
                } catch (Error e) { if (!(e is Gtk.DialogError.DISMISSED)) result_label.label = _("File selection failed: %s").printf(e.message); }
                refresh();
            });
        }

        private void attach_iso(string? local_path) {
            if (busy || pending || drive.selected >= empty_drives.length) return;
            string target = empty_drives[(int)drive.selected].id;
            if (local_path == null) download_cancel = new Cancellable();
            var cancellation = download_cancel;
            run(() => {
                var image = local_path == null ? packages.fetch(true, cancellation) : GuestToolsPackages.local_file(local_path, true);
                if (cancellation != null) cancellation.set_error_if_cancelled();
                media.attach(vm, image.path, target);
                Idle.add(() => {
                    if (!dismissed) {
                        empty_drives = new GenericArray<GuestOpticalDrive>();
                        media_label.label = _("VirtIO ISO attached. Open the Windows console and run virtio-win-guest-tools.exe from the CD drive as administrator, keeping Balloon and QEMU Guest Agent selected. Reopen this dialog after setup.");
                        result_label.label = _("ISO package: %s\nSHA256: %s").printf(image.version, image.sha256);
                    }
                    return Source.REMOVE;
                });
            });
        }
    }
}
