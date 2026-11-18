namespace Rigs {
    public class CommandResult : Object {
        public string output;
        public string error_output;
        public int exit_status;

        public CommandResult(string output = "", string error_output = "", int exit_status = 0) {
            this.output = output;
            this.error_output = error_output;
            this.exit_status = exit_status;
        }
    }

    public class HostCommand : Object {
        public string mode { get; private set; }
        public string snap_root { get; private set; }

        private class Deadline : Object {
            public Mutex mutex = Mutex();
            public Cond cond = Cond();
            public bool finished = false;
            public bool expired = false;
        }

        public HostCommand(string? mode_override = null, string? snap_root_override = null) {
            snap_root = snap_root_override ?? Environment.get_variable("SNAP") ?? "/snap/rigs/current";
            mode = mode_override ?? detect_mode();
        }

        private static string detect_mode() {
            if (FileUtils.test("/.flatpak-info", FileTest.EXISTS) ||
                Environment.get_variable("FLATPAK_ID") != null)
                return "flatpak";
            string? snap = Environment.get_variable("SNAP");
            if (snap == null) return "native";
            try {
                string manifest;
                FileUtils.get_contents(Path.build_filename(snap, "meta", "snap.yaml"), out manifest);
                foreach (string line in manifest.split("\n")) {
                    if (line.strip() == "confinement: classic") return "snap-classic";
                }
            } catch (FileError e) {
                // Missing or unreadable confinement metadata is never permission to escape.
            }
            if (FileUtils.test(Path.build_filename(snap, "docker-snap", "bin", "docker"), FileTest.IS_EXECUTABLE))
                return "snap-docker";
            return "snap-restricted";
        }

        public string[] prepare(string[] argv, string? directory = null) throws Error {
            if (argv.length == 0 || argv[0].length == 0)
                throw new IOError.INVALID_ARGUMENT("A host command requires an executable.");
            if (mode == "snap-restricted")
                throw new IOError.NOT_SUPPORTED("Restricted Snap supports only the connected Docker runtime. Install the Docker Snap and connect rigs:docker to docker:docker-daemon and rigs:docker-executables to docker:docker-executables. Use the native package for other host resources or custom scripts.");
            if (mode == "snap-docker") {
                if (argv[0] != "docker")
                    throw new IOError.NOT_SUPPORTED("Restricted Snap supports only the connected Docker runtime. Use the native package for Podman, libvirt, or custom host scripts.");
                string[] prepared = { Path.build_filename(snap_root, "docker-snap", "bin", "docker") };
                for (int i = 1; i < argv.length; i++) prepared += argv[i];
                return prepared;
            }
            if (mode == "flatpak") {
                string[] prepared = { "flatpak-spawn", "--host", "--watch-bus", "--env=LC_ALL=C" };
                if (directory != null) prepared += "--directory=" + directory;
                prepared += "--";
                foreach (string arg in argv) prepared += arg;
                return prepared;
            }
            if (mode != "native" && mode != "snap-classic")
                throw new IOError.NOT_SUPPORTED("Unknown host command execution mode.");
            return argv;
        }

        private SubprocessLauncher launcher(SubprocessFlags flags, string? directory) {
            var result = new SubprocessLauncher(flags);
            result.setenv("LC_ALL", "C", true);
            if (mode != "flatpak" && directory != null) result.set_cwd(directory);
            return result;
        }

        public virtual CommandResult run(string[] argv, string? directory = null, uint timeout_ms = 3000) throws Error {
            string[] prepared = prepare(argv, directory);
            var process = launcher(SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE, directory).spawnv(prepared);
            var cancellable = new Cancellable();
            var deadline = new Deadline();
            int64 expires = get_monotonic_time() + (int64)timeout_ms * 1000;
            var watchdog = new Thread<void*>("host-command-deadline", () => {
                deadline.mutex.lock();
                while (!deadline.finished) {
                    if (!deadline.cond.wait_until(deadline.mutex, expires) && !deadline.finished) {
                        deadline.expired = true;
                        cancellable.cancel();
                        process.force_exit();
                        break;
                    }
                }
                deadline.mutex.unlock();
                return null;
            });
            string? output = null;
            string? error_output = null;
            Error? failure = null;
            try {
                process.communicate_utf8(null, cancellable, out output, out error_output);
            } catch (Error e) {
                failure = e;
                process.force_exit();
            }
            deadline.mutex.lock();
            deadline.finished = true;
            deadline.cond.signal();
            deadline.mutex.unlock();
            watchdog.join();
            // Cancellation stops pipe communication; close both pipes and reap our child.
            try { process.get_stdout_pipe().close(); } catch (Error e) {}
            try { process.get_stderr_pipe().close(); } catch (Error e) {}
            process.wait(null);
            if (deadline.expired)
                throw new IOError.TIMED_OUT("Host command exceeded its %u ms deadline.", timeout_ms);
            if (failure != null) throw failure;
            int status = process.get_if_exited() ? process.get_exit_status() : 128 + process.get_term_sig();
            return new CommandResult(output ?? "", error_output ?? "", status);
        }

        // Waits for the process without a deadline: startup commands may legitimately pull images for minutes.
        public virtual CommandResult run_to_completion(string[] argv, string? directory = null) throws Error {
            string[] prepared = prepare(argv, directory);
            var process = launcher(SubprocessFlags.STDOUT_PIPE | SubprocessFlags.STDERR_PIPE, directory).spawnv(prepared);
            string? output = null;
            string? error_output = null;
            process.communicate_utf8(null, null, out output, out error_output);
            int status = process.get_if_exited() ? process.get_exit_status() : 128 + process.get_term_sig();
            return new CommandResult(output ?? "", error_output ?? "", status);
        }

        public virtual void launch(string[] argv, string? directory = null) throws Error {
            string[] prepared = prepare(argv, directory);
            launcher(SubprocessFlags.NONE, directory).spawnv(prepared);
        }
    }
}
