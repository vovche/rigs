namespace Rigs.Tests {
    public class TestHostCommand {
        private static void assert_argv(string[] actual, string[] expected) {
            assert(actual.length == expected.length);
            for (int i = 0; i < expected.length; i++) assert(actual[i] == expected[i]);
        }

        public static void test_prepare() {
            try {
                string[] argv = { "/path with spaces/tool", "literal ; $HOME && |" };
                assert_argv(new HostCommand("native").prepare(argv, "/directory with spaces"), argv);
                assert_argv(new HostCommand("snap-classic").prepare(argv), argv);
                assert_argv(new HostCommand("flatpak").prepare(argv, "/directory with spaces"), {
                    "flatpak-spawn", "--host", "--watch-bus", "--env=LC_ALL=C",
                    "--directory=/directory with spaces", "--", "/path with spaces/tool", "literal ; $HOME && |"
                });
                assert_argv(new HostCommand("flatpak").prepare({ "tool" }), {
                    "flatpak-spawn", "--host", "--watch-bus", "--env=LC_ALL=C", "--", "tool"
                });
                assert_argv(new HostCommand("snap-docker", "/snap root/rigs/42").prepare({
                    "docker", "inspect", "container with spaces", "literal ; $HOME && |"
                }), {
                    "/snap root/rigs/42/docker-snap/bin/docker", "inspect",
                    "container with spaces", "literal ; $HOME && |"
                });
                var connected = new HostCommand("snap-docker");
                assert_argv(connected.prepare({ "docker", "ps" }), {
                    Path.build_filename(connected.snap_root, "docker-snap", "bin", "docker"), "ps"
                });
            } catch (Error e) { assert_not_reached(); }
            try {
                new HostCommand("snap-restricted").prepare({ "tool" });
                assert_not_reached();
            } catch (Error e) { assert(e is IOError.NOT_SUPPORTED); }
            string[] unsupported = { "podman", "virsh", "/bin/bash", "/usr/bin/docker", "docker; sh" };
            foreach (string executable in unsupported) {
                try {
                    new HostCommand("snap-docker").prepare({ executable });
                    assert_not_reached();
                } catch (Error e) { assert(e is IOError.NOT_SUPPORTED); }
            }
            try {
                new HostCommand("native").prepare({});
                assert_not_reached();
            } catch (Error e) { assert(e is IOError.INVALID_ARGUMENT); }
        }

        public static void test_native() {
            try {
                var host = new HostCommand("native");
                var literal = host.run({ "/usr/bin/printf", "%s", "a ; $HOME && | > b" });
                assert(literal.output == "a ; $HOME && | > b");
                assert(literal.error_output == "" && literal.exit_status == 0);
                var locale = host.run({ "/usr/bin/printenv", "LC_ALL" });
                assert(locale.output == "C\n" && locale.exit_status == 0);
                var cwd = host.run({ "/bin/pwd" }, "/tmp");
                assert(cwd.output == "/tmp\n");
                var failed = host.run({ "/bin/sh", "-c", "printf failure >&2; exit 7" });
                assert(failed.output == "" && failed.error_output == "failure");
                assert(failed.exit_status == 7);
            } catch (Error e) { assert_not_reached(); }
        }

        public static void test_timeout() {
            int64 started = get_monotonic_time();
            try {
                new HostCommand("native").run({ "/bin/sleep", "5" }, null, 30);
                assert_not_reached();
            } catch (Error e) { assert(e is IOError.TIMED_OUT); }
            int64 elapsed = get_monotonic_time() - started;
            assert(elapsed >= 20000 && elapsed < 500000);
        }
    }
}
