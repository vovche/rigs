using GLib.Intl;

namespace Rigs {
    public class GuestToolsArtifact : Object {
        public string path;
        public string sha256;
        public string version;
        public bool iso;
        public GuestToolsArtifact(string path, string sha256, string version = "", bool iso = false) {
            this.path = path; this.sha256 = sha256; this.version = version; this.iso = iso;
        }
    }

    // Catalog updates are reviewed code changes, never an unsigned "latest" manifest.
    public class GuestToolsPackages : Object {
        public const string VERSION = "0.1.302-1";
        public const string SOURCE = "https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/archive-virtio/virtio-win-0.1.302-1/";
        public const string EXE_SHA256 = "d8ae9ea1e943384ac195e012cd36f82c3161620e5fc9529be4e42e6f420e222d";
        public const string ISO_SHA256 = "303f7ae40dad495d6ae474fdc571df58958a4dbc5c37a522d80f9a203867949d";
        private string cache_dir;
        private Soup.Session session;
        public signal void progress(int64 received, int64 total);

        public GuestToolsPackages(string? cache_dir = null) {
            this.cache_dir = cache_dir ?? Path.build_filename(Environment.get_user_cache_dir(), "rigs", "guest-tools", VERSION);
            session = new Soup.Session();
            session.timeout = 30;
            session.user_agent = "Rigs/" + Config.VERSION;
        }

        protected virtual string expected_hash(bool iso) { return iso ? ISO_SHA256 : EXE_SHA256; }
        protected virtual InputStream download(string uri, Cancellable? cancel, out int64 length) throws Error {
            var message = new Soup.Message("GET", uri);
            message.flags |= Soup.MessageFlags.NO_REDIRECT;
            var input = session.send(message, cancel);
            if (message.status_code != 200) {
                input.close();
                throw new IOError.FAILED(_("The official VirtIO download is unavailable. Try again or choose a local file."));
            }
            length = message.response_headers.get_content_length();
            return input;
        }

        public static GuestToolsArtifact local_file(string path, bool iso, string expected = "") throws Error {
            var file = File.new_for_path(path);
            var info = file.query_info("standard::type,standard::size", FileQueryInfoFlags.NONE);
            if (info.get_file_type() != FileType.REGULAR || info.get_size() <= 0 ||
                info.get_size() > (iso ? 2147483648L : 268435456L))
                throw new IOError.INVALID_DATA(_("Choose a regular VirtIO installer or ISO within the supported size limit."));
            if (iso) GuestMedia.validate_iso(path);
            var stream = file.read();
            var checksum = new Checksum(ChecksumType.SHA256);
            uint8[] buffer = new uint8[65536];
            ssize_t count;
            bool first = true;
            try {
                while ((count = stream.read(buffer)) > 0) {
                    if (first && !iso && (count < 2 || buffer[0] != 'M' || buffer[1] != 'Z'))
                        throw new IOError.INVALID_DATA(_("The selected file is not a Windows executable installer."));
                    first = false;
                    checksum.update(buffer, (size_t)count);
                }
            } finally { try { stream.close(); } catch (Error e) { } }
            string digest = checksum.get_string();
            if (expected.length > 0 && digest != expected.down())
                throw new IOError.INVALID_DATA(_("VirtIO package checksum verification failed. The file will not be used."));
            return new GuestToolsArtifact(path, digest, expected.length > 0 ? VERSION : _("Local file"), iso);
        }

        private class DownloadDeadline : Object {
            public Mutex mutex = Mutex();
            public Cond cond = Cond();
            public bool finished = false;
        }

        public virtual GuestToolsArtifact fetch(bool iso, Cancellable? cancel = null) throws Error {
            var cancellation = new Cancellable();
            ulong cancel_handler = 0;
            if (cancel != null) {
                cancel_handler = cancel.cancelled.connect(() => { cancellation.cancel(); });
                if (cancel.is_cancelled()) cancellation.cancel();
            }
            var state = new DownloadDeadline();
            int64 deadline = get_monotonic_time() + 1800L * 1000000;
            var watchdog = new Thread<void*>("virtio-download-deadline", () => {
                state.mutex.lock();
                while (!state.finished) {
                    if (!state.cond.wait_until(state.mutex, deadline) && !state.finished) {
                        cancellation.cancel();
                        break;
                    }
                }
                state.mutex.unlock();
                return null;
            });
            try {
                return fetch_file(iso, cancellation);
            } finally {
                state.mutex.lock();
                state.finished = true;
                state.cond.signal();
                state.mutex.unlock();
                watchdog.join();
                if (cancel != null && cancel_handler != 0) cancel.disconnect(cancel_handler);
            }
        }

        private GuestToolsArtifact fetch_file(bool iso, Cancellable? cancel) throws Error {
            string expected = expected_hash(iso);
            if (!Regex.match_simple("\\A[0-9a-f]{64}\\z", expected))
                throw new IOError.NOT_SUPPORTED(_("No verified package is available for this download."));
            string filename = iso ? "virtio-win-0.1.302.iso" : "virtio-win-guest-tools.exe";
            if (DirUtils.create_with_parents(cache_dir, 0700) != 0)
                throw new IOError.FAILED(_("Cannot create the VirtIO download cache."));
            string path = Path.build_filename(cache_dir, filename);
            if (FileUtils.test(path, FileTest.EXISTS)) {
                try { return local_file(path, iso, expected); }
                catch (Error e) { /* Replace only after a fresh download verifies. */ }
            }
            string partial = Path.build_filename(cache_dir, ".part-" + Uuid.string_random() + "-" + filename);
            FileOutputStream? output = null;
            InputStream? input = null;
            try {
                output = File.new_for_path(partial).create(FileCreateFlags.PRIVATE, cancel);
                int64 length;
                input = download(SOURCE + filename, cancel, out length);
                int64 limit = iso ? 2147483648L : 268435456L;
                if (length > limit) throw new IOError.INVALID_DATA(_("The VirtIO download exceeds the supported size limit."));
                int64 received = 0;
                int64 last_progress = 0;
                var checksum = new Checksum(ChecksumType.SHA256);
                uint8[] buffer = new uint8[65536];
                ssize_t count;
                while ((count = input.read(buffer, cancel)) > 0) {
                    received += count;
                    if (received > limit) throw new IOError.INVALID_DATA(_("The VirtIO download exceeds the supported size limit."));
                    size_t written;
                    output.write_all(buffer[0:(int)count], out written, cancel);
                    checksum.update(buffer, (size_t)count);
                    if (get_monotonic_time() - last_progress > 250000) {
                        progress(received, length);
                        last_progress = get_monotonic_time();
                    }
                }
                input.close(); input = null;
                output.close(); output = null;
                if (received == 0 || (length > 0 && length != received) || checksum.get_string() != expected)
                    throw new IOError.INVALID_DATA(_("VirtIO package checksum verification failed. The file will not be used."));
                var artifact = local_file(partial, iso, expected);
                File.new_for_path(partial).move(File.new_for_path(path), FileCopyFlags.OVERWRITE, cancel);
                artifact.path = path;
                progress(received, received);
                return artifact;
            } finally {
                if (input != null) { try { input.close(); } catch (Error e) { } }
                if (output != null) { try { output.close(); } catch (Error e) { } }
                if (FileUtils.test(partial, FileTest.EXISTS)) FileUtils.unlink(partial);
            }
        }
    }
}
