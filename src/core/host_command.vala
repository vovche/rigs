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

    // Where Rigs runs decides how (and whether) it may execute host programs.
    public enum ExecutionMode {
        NATIVE,               // distro package or ./build.sh: run argv directly
        SNAP_CLASSIC,         // classic Snap: like native
        SNAP_DOCKER,          // strict Snap with the Docker Snap connected: only `docker`
        SNAP_RESTRICTED,      // strict Snap without Docker: nothing on the host
        UNSUPPORTED_SANDBOX;  // Flatpak: refused with an explicit error

        // /proc of the host (QEMU process status) is visible only outside a sandbox.
        public bool sees_host_processes() {
            return this == ExecutionMode.NATIVE || this == ExecutionMode.SNAP_CLASSIC;
        }

        public bool is_snap() {
            return this == ExecutionMode.SNAP_CLASSIC || this == ExecutionMode.SNAP_DOCKER ||
                this == ExecutionMode.SNAP_RESTRICTED;
        }

        public string to_label() {
            switch (this) {
                case ExecutionMode.SNAP_CLASSIC: return "snap-classic";
                case ExecutionMode.SNAP_DOCKER: return "snap-docker";
                case ExecutionMode.SNAP_RESTRICTED: return "snap-restricted";
                case ExecutionMode.UNSUPPORTED_SANDBOX: return "unsupported-sandbox";
                default: return "native";
            }
        }
    }

    public class HostCommand : Object {
        public ExecutionMode mode { get; private set; }
        public string snap_root { get; private set; }

        private class Deadline : Object {
            public Mutex mutex = Mutex();
            public Cond cond = Cond();
            public bool finished = false;
            public bool expired = false;
        }

        // Tests pass a mode; the app detects it from the environment.
        public HostCommand.with_mode(ExecutionMode mode, string? snap_root_override = null) {
            snap_root = snap_root_override ?? Environment.get_variable("SNAP") ?? "/snap/rigs/current";
            this.mode = mode;
        }

        public HostCommand() {
            this.with_mode(detect_mode());
        }

        private static ExecutionMode detect_mode() {
            // Flatpak is not a supported delivery channel: say so instead of failing obscurely.
            if (FileUtils.test("/.flatpak-info", FileTest.EXISTS) ||
                Environment.get_variable("FLATPAK_ID") != null)
                return ExecutionMode.UNSUPPORTED_SANDBOX;
            string? snap = Environment.get_variable("SNAP");
            if (snap == null) return ExecutionMode.NATIVE;
            try {
                string manifest;
                FileUtils.get_contents(Path.build_filename(snap, "meta", "snap.yaml"), out manifest);
                foreach (string line in manifest.split("\n")) {
                    if (line.strip() == "confinement: classic") return ExecutionMode.SNAP_CLASSIC;
                }
            } catch (FileError e) {
                // Missing or unreadable confinement metadata is never permission to escape.
            }
            if (FileUtils.test(Path.build_filename(snap, "docker-snap", "bin", "docker"), FileTest.IS_EXECUTABLE))
                return ExecutionMode.SNAP_DOCKER;
            return ExecutionMode.SNAP_RESTRICTED;
        }

        public string[] prepare(string[] argv, string? directory = null) throws Error {
            if (argv.length == 0 || argv[0].length == 0)
                throw new IOError.INVALID_ARGUMENT("A host command requires an executable.");
            if (mode == ExecutionMode.SNAP_RESTRICTED)
                throw new IOError.NOT_SUPPORTED("Restricted Snap supports only the connected Docker runtime. Install the Docker Snap and connect rigs:docker to docker:docker-daemon and rigs:docker-executables to docker:docker-executables. Use the native package for other host resources or custom scripts.");
            if (mode == ExecutionMode.SNAP_DOCKER) {
                if (argv[0] != "docker")
                    throw new IOError.NOT_SUPPORTED("Restricted Snap supports only the connected Docker runtime. Use the native package for Podman, libvirt, or custom host scripts.");
                string[] prepared = { Path.build_filename(snap_root, "docker-snap", "bin", "docker") };
                for (int i = 1; i < argv.length; i++) prepared += argv[i];
                return prepared;
            }
            if (mode == ExecutionMode.UNSUPPORTED_SANDBOX)
                throw new IOError.NOT_SUPPORTED("Rigs does not support Flatpak. Install the native package or the Snap.");
            return argv;
        }

        private SubprocessLauncher launcher(SubprocessFlags flags, string? directory) {
            var result = new SubprocessLauncher(flags);
            result.setenv("LC_ALL", "C", true);
            if (directory != null) result.set_cwd(directory);
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
            Bytes? output = null;
            Bytes? error_output = null;
            Error? failure = null;
            try {
                process.communicate(null, cancellable, out output, out error_output);
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
            return new CommandResult(bytes_to_text(output), bytes_to_text(error_output), status);
        }

        // Output may come from any program (logs, QEMU, Windows guests): never assume UTF-8.
        public static string bytes_to_text(Bytes? bytes) {
            if (bytes == null || bytes.get_size() == 0) return "";
            unowned uint8[] data = bytes.get_data();
            return ((string) data).substring(0, data.length).make_valid();
        }

        public const int CAPTURE_TAIL_BYTES = 65536;

        // For user start scripts that may background long-lived children:
        // output goes to a private file (children inheriting it cannot block us),
        // only the direct child is awaited, and only the last CAPTURE_TAIL_BYTES are read.
        public virtual CommandResult run_capture_tail(string[] argv, string? directory = null) throws Error {
            string[] prepared = prepare(argv, directory);
            string log_path;
            int fd = FileUtils.open_tmp("rigs-start-XXXXXX.log", out log_path);
            FileUtils.unlink(log_path);
            int err_fd = Posix.dup(fd);
            var launch = launcher(SubprocessFlags.NONE, directory);
            launch.take_stdout_fd(fd);
            launch.take_stderr_fd(err_fd);
            int status;
            int read_fd = Posix.dup(fd);
            try {
                var process = launch.spawnv(prepared);
                launch.close();
                process.wait(null);
                status = process.get_if_exited() ? process.get_exit_status() : 128 + process.get_term_sig();
            } catch (Error e) {
                Posix.close(read_fd);
                throw e;
            }
            string text = read_tail(read_fd, CAPTURE_TAIL_BYTES);
            Posix.close(read_fd);
            return new CommandResult("", text, status);
        }

        private static string read_tail(int fd, int limit) {
            Posix.off_t size = Posix.lseek(fd, 0, Posix.SEEK_END);
            if (size <= 0) return "";
            Posix.off_t start = size > limit ? size - limit : 0;
            Posix.lseek(fd, start, Posix.SEEK_SET);
            var buffer = new uint8[(int)(size - start)];
            ssize_t total = 0;
            while (total < buffer.length) {
                ssize_t n = Posix.read(fd, (void*)((uint8*)buffer + total), buffer.length - total);
                if (n <= 0) break;
                total += n;
            }
            return bytes_to_text(new Bytes(buffer[0:(int)total]));
        }
    }
}
