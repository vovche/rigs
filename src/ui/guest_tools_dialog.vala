using GLib.Intl;

namespace Rigs {
    public class GuestToolsDialog : Adw.Dialog {
        public signal void settings_saved();

        public static string describe(GuestMemoryState state) {
            switch (state) {
                case GuestMemoryState.READY: return _("Guest statistics are connected");
                case GuestMemoryState.NOT_CONFIGURED: return _("Guest statistics need to be configured");
                case GuestMemoryState.CONNECTION_UNAVAILABLE: return _("Cannot connect to the guest statistics channel");
                case GuestMemoryState.DEVICE_MISSING: return _("The balloon0 statistics device is missing");
                case GuestMemoryState.GUEST_NOT_REPORTING: return _("The guest is not reporting statistics yet");
                case GuestMemoryState.STALE: return _("Guest statistics have stopped updating");
                default: return _("The guest does not provide the required memory counters");
            }
        }

        public GuestToolsDialog(Resource resource, GuestMemoryState state) {
            title = _("Guest Integration");
            content_width = 580;
            content_height = 600;
            var root = new Gtk.Box(Gtk.Orientation.VERTICAL, 0);
            set_child(root);
            var header = new Adw.HeaderBar();
            root.append(header);
            var save = new Gtk.Button.with_label(_("Save and Check"));
            save.add_css_class("suggested-action");
            header.pack_end(save);
            var scrolled = new Gtk.ScrolledWindow();
            scrolled.vexpand = true;
            root.append(scrolled);
            var page = new Adw.PreferencesPage();
            scrolled.set_child(page);
            var status = new Adw.PreferencesGroup();
            status.title = resource.name;
            status.description = describe(state);
            page.add(status);
            var guidance = new Gtk.Label(resource.kind == ResourceKind.LIBVIRT
                ? _("Choose the guest OS. Rigs reads memory statistics through libvirt. Ensure the domain has a VirtIO memory balloon device; use your VM manager to add it if needed, then restart the VM. No separate QMP socket is needed.")
                : _("Choose the guest OS and the host path of its QMP socket. Host memory and guest memory are measured separately."));
            guidance.wrap = true;
            guidance.xalign = 0;
            status.add(guidance);
            var settings = new Adw.PreferencesGroup();
            settings.title = _("Statistics Connection");
            page.add(settings);
            var os = new Adw.ComboRow();
            os.title = _("Guest Operating System");
            os.model = new Gtk.StringList({_("Choose an operating system"), "Windows", "Linux"});
            os.selected = resource.guest_os == "windows" ? 1 : resource.guest_os == "linux" ? 2 : 0;
            settings.add(os);
            var socket = new Adw.EntryRow();
            socket.title = _("QMP Socket on the Host");
            socket.text = resource.qmp_socket;
            socket.visible = resource.kind != ResourceKind.LIBVIRT;
            settings.add(socket);
            var agent_socket = new Adw.EntryRow();
            agent_socket.title = _("Guest Agent Socket on the Host");
            agent_socket.text = resource.guest_agent_socket;
            agent_socket.visible = resource.kind != ResourceKind.LIBVIRT;
            settings.add(agent_socket);
            os.notify["selected"].connect(() => {
                save.sensitive = valid_settings(resource, os, socket, agent_socket);
            });
            socket.notify["text"].connect(() => {
                save.sensitive = valid_settings(resource, os, socket, agent_socket);
            });
            agent_socket.notify["text"].connect(() => { save.sensitive = valid_settings(resource, os, socket, agent_socket); });
            save.sensitive = valid_settings(resource, os, socket, agent_socket);
            var help = new Adw.PreferencesGroup();
            help.title = _("Guest Drivers and Services");
            help.description = _("Missing statistics alone do not prove that a driver is missing. Check the connection, device and guest service before installing anything.");
            page.add(help);
            var windows = new Adw.ActionRow();
            windows.title = _("Windows: VirtIO Balloon Driver");
            windows.subtitle = _("Install the Balloon driver from VirtIO-Win, then check that BalloonService is running. Wait a few seconds for the first sample.");
            windows.subtitle_lines = 0;
            var downloads = new Gtk.Button.with_label(_("Set Up Windows Drivers…"));
            downloads.valign = Gtk.Align.CENTER;
            downloads.clicked.connect(() => {
                if (!valid_settings(resource, os, socket, agent_socket)) return;
                save_connection(resource, os, socket, agent_socket);
                new GuestDriverSetupDialog(resource).present(this);
            });
            downloads.sensitive = os.selected == 1 && save.sensitive;
            save.notify["sensitive"].connect(() => { downloads.sensitive = os.selected == 1 && save.sensitive; });
            os.notify["selected"].connect(() => { downloads.sensitive = os.selected == 1 && save.sensitive; });
            windows.add_suffix(downloads);
            help.add(windows);
            var linux_row = new Adw.ActionRow();
            linux_row.title = _("Linux: VirtIO Balloon Driver");
            linux_row.subtitle = _("Check that the virtio_balloon kernel driver is loaded and the VM has a balloon device. A paused guest may stop reporting statistics.");
            linux_row.subtitle_lines = 0;
            help.add(linux_row);
            var qemu = new Adw.PreferencesGroup();
            qemu.title = _("QEMU Launch Configuration");
            qemu.description = _("The VM needs a virtio-balloon device named balloon0 and a local QMP socket. Add these options in your VM manager or launch configuration, then restart the VM. Keep any existing balloon device; do not add a duplicate.");
            qemu.visible = resource.kind != ResourceKind.LIBVIRT;
            page.add(qemu);
            var options = new Gtk.Label("-device virtio-balloon-pci,id=balloon0,guest-stats-polling-interval=5\n-qmp unix:/path/to/qmp.sock,server=on,wait=off");
            options.add_css_class("monospace");
            options.selectable = true;
            options.wrap = true;
            options.xalign = 0;
            qemu.add(options);
            var agent_help = new Adw.PreferencesGroup();
            agent_help.title = _("Guest Agent Channel");
            agent_help.description = resource.kind == ResourceKind.LIBVIRT
                ? _("In your VM manager, add a VirtIO channel named org.qemu.guest_agent.0. Install QEMU Guest Agent in Windows from the VirtIO ISO. Rigs then uses the libvirt agent connection without Windows passwords.")
                : _("Guest Agent uses a separate socket from QMP. Configure a VirtIO serial channel named org.qemu.guest_agent.0 before the first agent installation. Keep existing controllers and channels; do not add duplicates.");
            page.add(agent_help);
            if (resource.kind != ResourceKind.LIBVIRT) {
                var agent_options = new Gtk.Label("-chardev socket,id=qga0,path=/path/to/qga.sock,server=on,wait=off\n-device virtio-serial-pci\n-device virtserialport,chardev=qga0,name=org.qemu.guest_agent.0");
                agent_options.add_css_class("monospace");
                agent_options.selectable = true;
                agent_options.wrap = true;
                agent_options.xalign = 0;
                agent_help.add(agent_options);
            }
            save.clicked.connect(() => {
                save_connection(resource, os, socket, agent_socket);
                close();
            });
        }

        private bool valid_settings(Resource resource, Adw.ComboRow os, Adw.EntryRow qmp, Adw.EntryRow agent) {
            if (os.selected == 0) return false;
            if (resource.kind == ResourceKind.LIBVIRT) return true;
            return (qmp.text.strip().length == 0 || qmp.text.strip().has_prefix("/")) &&
                (agent.text.strip().length == 0 || agent.text.strip().has_prefix("/"));
        }

        private void save_connection(Resource resource, Adw.ComboRow os, Adw.EntryRow qmp, Adw.EntryRow agent) {
            resource.guest_os = os.selected == 1 ? "windows" : "linux";
            if (resource.kind != ResourceKind.LIBVIRT) {
                resource.qmp_socket = qmp.text.strip();
                resource.guest_agent_socket = agent.text.strip();
            }
            settings_saved();
        }
    }
}
