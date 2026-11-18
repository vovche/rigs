/* test_resource_presets.vala — ready-made settings read from real-world folder layouts. */
using Rigs;

namespace Rigs.Tests {
    public class TestResourcePresets {
        // Shape of a real run-vm.sh: variables, quoted expansions, continued lines, -name with process=.
        private const string SCRIPT = """#!/bin/bash
SPICE_SOCK="/tmp/omarchy-spice.sock"
MONITOR_SOCK="/tmp/omarchy-monitor.sock"
GA_SOCK=/tmp/omarchy-ga.sock
# -monitor unix:/commented/out
exec qemu-system-x86_64 \
  -name omarchy-quattro,process=omarchy-qemu \
  -m 8192 \
  -spice unix=on,addr="$SPICE_SOCK",port=5930,disable-ticketing=on \
  -chardev socket,id=cga,path="${GA_SOCK}",server=on,wait=off \
  -device virtserialport,chardev=cga,name=org.qemu.guest_agent.0 \
  -qmp unix:path=/tmp/omarchy-qmp.sock,server=on \
  -monitor unix:"$MONITOR_SOCK",server=on,wait=off
""";

        private const string COMPOSE = """services:
  windows:
    image: dockurr/windows
    container_name: tiny10-vm
    ports:
      - "8007:8006"             # Web VNC Interface (port 8007)
      - "3390:3389/tcp"         # RDP
      - "3390:3389/udp"
      - 127.0.0.1:5985:5985
    volumes:
      - ./storage:/storage
""";

        public static void test_qemu_script() {
            var r = ResourcePresets.from_qemu_script("/vms/omarchy", SCRIPT);
            assert(r.kind == ResourceKind.QEMU && r.start_cmd == "./run-vm.sh");
            assert(r.name == "omarchy");
            assert(r.process_match == "omarchy-qemu");
            assert(r.monitor_socket == "/tmp/omarchy-monitor.sock");
            assert(r.qmp_socket == "/tmp/omarchy-qmp.sock");
            assert(r.guest_agent_socket == "/tmp/omarchy-ga.sock");
            assert(r.connect_cmd == "remote-viewer spice+unix:///tmp/omarchy-spice.sock");
            // TCP SPICE and a plain -name.
            r = ResourcePresets.from_qemu_script("/vms/x", "qemu-system-x86_64 -name win7 -spice port=5931,disable-ticketing=on");
            assert(r.process_match == "win7" && r.connect_cmd == "remote-viewer spice://127.0.0.1:5931");
            // Nothing recognizable: fields stay empty instead of guessed.
            r = ResourcePresets.from_qemu_script("/vms/y", "echo hello");
            assert(r.process_match == "" && r.monitor_socket == "" && r.connect_cmd == "");
        }

        public static void test_compose() {
            var r = ResourcePresets.from_compose("/vms/tiny10", COMPOSE, ContainerRuntime.DOCKER);
            assert(r.kind == ResourceKind.COMPOSE && r.runtime == ContainerRuntime.DOCKER);
            assert(r.container_name == "tiny10-vm" && r.guest_os == "windows");
            assert(r.details == "Web VNC Interface :8007 • RDP :3390 • :5985");
            assert(r.start_cmd == "" && r.stop_cmd == ""); // driver default: <runtime> compose up -d / down
            assert(ResourcePresets.compose_host_port("./storage:/storage") == "");
            assert(ResourcePresets.compose_host_port("70000:1") == "");
        }

        public static void test_validate() {
            try {
                string dir = DirUtils.make_tmp("rigs-preset-XXXXXX");
                var r = ResourcePresets.for_folder(dir);
                assert(r.kind == ResourceKind.COMPOSE && r.name == Path.get_basename(dir));
                assert(ResourcePresets.validate(r) != null);               // no compose.yaml, no start command
                r.start_cmd = "./vmctl.sh up";
                assert(ResourcePresets.validate(r) != null);               // ./vmctl.sh is not in the folder
                FileUtils.set_contents(Path.build_filename(dir, "vmctl.sh"), "#!/bin/sh\n");
                assert(ResourcePresets.validate(r) == null);
                r.container_name = "bad name";
                assert(ResourcePresets.validate(r) != null);
                r.container_name = "";
                r.monitor_socket = "relative.sock";
                assert(ResourcePresets.validate(r) != null);
                r.monitor_socket = "";
                r.name = "  ";
                assert(ResourcePresets.validate(r) != null);

                string compose = Path.build_filename(dir, "compose.yaml");
                FileUtils.set_contents(compose, COMPOSE);
                r = ResourcePresets.for_folder(dir);
                assert(r.container_name == "tiny10-vm" && ResourcePresets.validate(r) == null);
                FileUtils.unlink(compose);

                string script = Path.build_filename(dir, "run-vm.sh");
                FileUtils.set_contents(script, SCRIPT);
                r = ResourcePresets.for_folder(dir);
                assert(r.kind == ResourceKind.QEMU && ResourcePresets.validate(r) == null);
                FileUtils.unlink(script);
                assert(ResourcePresets.validate(r) != null);                // run-vm.sh is gone
                FileUtils.unlink(Path.build_filename(dir, "vmctl.sh"));
                DirUtils.remove(dir);

                var container = ResourcePresets.blank(ResourceKind.CONTAINER);
                container.name = "c";
                container.resource_id = "--all";
                assert(ResourcePresets.validate(container) != null);
            } catch (Error e) { assert_not_reached(); }
        }
    }
}
