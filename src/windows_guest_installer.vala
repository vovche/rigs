using GLib.Intl;

namespace Rigs {
    public class GuestToolsProbe : Object {
        public bool available = false;
        public bool compatible = false;
        public bool administrator = false;
        public bool balloon_service_running = false;
        public string architecture = "";
        public string version = "";
        public string summary = "";
    }
    public enum GuestInstallState { SUCCEEDED, REBOOT_REQUIRED, FAILED, TIMED_OUT }
    public class GuestInstallResult : Object {
        public GuestInstallState state = GuestInstallState.FAILED;
        public string summary = "";
        public string journal_path = "";
        public string remote_directory = "";
        public int exit_code = -1;
    }
    public class WindowsGuestInstaller : Object {
        private GuestAgent agent;
        private string state_dir;
        private static Mutex active_mutex;
        private static HashTable<string, bool>? active;
        public uint poll_interval_ms { get; set; default = 100; }
        public signal void progress(string message);

        public WindowsGuestInstaller(GuestAgent? agent = null, string? state_dir = null) {
            this.agent = agent ?? new GuestAgent();
            this.state_dir = state_dir ?? Path.build_filename(Environment.get_user_state_dir(), "rigs", "guest-tools");
        }
        private static Json.Object object_node(Json.Node? node) throws Error {
            if (node == null || node.get_node_type() != Json.NodeType.OBJECT) throw new IOError.INVALID_DATA("Malformed or empty guest agent object.");
            return node.get_object();
        }
        private static Json.Node member(Json.Object obj, string name, Type type) throws Error {
            if (!obj.has_member(name)) throw new IOError.INVALID_DATA("Missing guest agent field.");
            var node = obj.get_member(name);
            if (node.get_node_type() != Json.NodeType.VALUE || node.get_value_type() != type)
                throw new IOError.INVALID_DATA("Malformed guest agent field.");
            return node;
        }
        private static string str(Json.Object obj, string name) throws Error { return member(obj, name, typeof(string)).get_string(); }
        private static bool flag(Json.Object obj, string name) throws Error { return member(obj, name, typeof(bool)).get_boolean(); }
        private static int64 number(Json.Object obj, string name) throws Error { return member(obj, name, typeof(int64)).get_int(); }
        private Json.Object call(VmModel vm, string name, Json.Object? args = null) throws Error {
            try { return object_node(agent.command(vm, name, args)); }
            catch (IOError.INVALID_DATA e) { throw new IOError.INVALID_DATA("Malformed response to %s.", name); }
        }
        private static string decode(string encoded) throws Error {
            if (!Regex.match_simple("\\A[A-Za-z0-9+/]*={0,2}\\z", encoded) || encoded.length % 4 != 0)
                throw new IOError.INVALID_DATA("Malformed guest base64 output.");
            uint8[] bytes = Base64.decode(encoded);
            int length = bytes.length;
            bytes.resize(length + 1);
            bytes[length] = 0;
            string text = (string)bytes;
            if (text.length != length || !text.validate()) throw new IOError.INVALID_DATA("Malformed guest text output.");
            return text;
        }
        private static string encoded_script(string source) throws Error {
            size_t read, written;
            string converted = GLib.convert(source, source.length, "UTF-16LE", "UTF-8", out read, out written);
            return Base64.encode(((uint8[])converted.data)[0:(int)written]);
        }
        private int64 execute(VmModel vm, string script) throws Error {
            var args = new Json.Object();
            args.set_string_member("path", "powershell.exe");
            var argv = new Json.Array();
            foreach (string arg in new string[] { "-NoProfile", "-NonInteractive", "-EncodedCommand", encoded_script(script) }) argv.add_string_element(arg);
            args.set_array_member("arg", argv);
            args.set_boolean_member("capture-output", true);
            int64 pid = number(call(vm, "guest-exec", args), "pid");
            if (pid <= 0 || pid > int.MAX) throw new IOError.INVALID_DATA("Malformed guest process identifier.");
            return pid;
        }
        private Json.Object? status(VmModel vm, int64 pid) throws Error {
            var args = new Json.Object(); args.set_int_member("pid", pid);
            var reply = call(vm, "guest-exec-status", args);
            if (!flag(reply, "exited")) return null;
            if (number(reply, "exitcode") != 0) throw new IOError.FAILED("Guest helper failed.");
            string output = decode(str(reply, "out-data"));
            var parser = new Json.Parser(); parser.load_from_data(output);
            return object_node(parser.get_root());
        }
        private void pause() { if (poll_interval_ms > 0) Thread.usleep((ulong)poll_interval_ms * 1000); }
        public static string preflight_script() {
            return "$ErrorActionPreference='Stop'; $a=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator); $s=Get-Service -Name BalloonService -ErrorAction SilentlyContinue; @{administrator=$a;balloon_service_running=($null -ne $s -and $s.Status -eq 'Running')} | ConvertTo-Json -Compress";
        }
        public GuestToolsProbe probe(VmModel vm) throws Error {
            var result = new GuestToolsProbe();
            var info = call(vm, "guest-info");
            if (!info.has_member("supported_commands") || info.get_member("supported_commands").get_node_type() != Json.NodeType.ARRAY)
                throw new IOError.INVALID_DATA("Missing guest agent capabilities.");
            var enabled = new HashTable<string, bool>(str_hash, str_equal);
            var list = info.get_array_member("supported_commands");
            for (uint i = 0; i < list.get_length(); i++) {
                var entry = object_node(list.get_element(i));
                if (flag(entry, "enabled")) enabled.insert(str(entry, "name"), true);
            }
            foreach (string name in new string[] { "guest-get-osinfo", "guest-exec", "guest-exec-status", "guest-file-open", "guest-file-write", "guest-file-read", "guest-file-close" }) {
                if (!enabled.contains(name)) { result.summary = _("Guest agent installation commands are unavailable or disabled."); return result; }
            }
            result.available = true;
            var os = call(vm, "guest-get-osinfo");
            result.architecture = str(os, "machine"); result.version = str(os, "version-id");
            result.compatible = str(os, "id") == "mswindows" && (result.architecture == "x86" || result.architecture == "x86_64") &&
                (result.version == "10" || result.version == "11" || result.version == "2016" || result.version == "2019" || result.version == "2022" || result.version == "2025");
            if (!result.compatible) { result.summary = _("This Windows version or architecture requires manual driver setup."); return result; }
            int64 pid = execute(vm, preflight_script());
            int64 end = get_monotonic_time() + 5000000;
            while (get_monotonic_time() < end) {
                var data = status(vm, pid);
                if (data != null) {
                    result.administrator = flag(data, "administrator");
                    result.balloon_service_running = flag(data, "balloon_service_running");
                    result.summary = result.administrator ? _("Windows guest is ready for driver installation.") : _("The Windows guest agent requires administrator privileges.");
                    return result;
                }
                pause();
            }
            throw new IOError.TIMED_OUT("Guest preflight timed out.");
        }
        private static string quote(string value) { return "'" + value.replace("'", "''") + "'"; }
        public static string install_script(string directory, string sha256) {
            var script = new StringBuilder("$ErrorActionPreference='Stop'; $d=");
            script.append(quote(directory));
            script.append("; $p=Join-Path $d 'guest-tools.exe'; $o=Join-Path $d 'outcome.json'; $r=@{code=-1;reboot=$false;service=$false;error=''}; $stage='hash'; try { ");
            script.append("if ((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne ");
            script.append(quote(sha256));
            script.append(") { throw 'Package hash mismatch' }; ");
            script.append("$stage='signature'; $s=Get-AuthenticodeSignature -LiteralPath $p; if ($s.Status -ne 'Valid' -or $null -eq $s.SignerCertificate) { throw 'Package signature invalid' }; ");
            script.append("$stage='signer'; $n=$s.SignerCertificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName,$false); ");
            script.append("if (@('Red Hat, Inc.','Red Hat, Inc','Red Hat Inc.','Red Hat Inc') -cnotcontains $n) { throw 'Package signer invalid' }; ");
            script.append("$stage='installer'; $log=Join-Path $d 'install.log'; $process=Start-Process -FilePath $p -ArgumentList @('/install','/quiet','/norestart','/log',('\"'+$log+'\"')) -Wait -PassThru; ");
            script.append("$r.code=$process.ExitCode; $r.reboot=($r.code -eq 3010); if ($r.code -eq 0) { $b=Get-Service -Name BalloonService -ErrorAction SilentlyContinue; $r.service=($null -ne $b -and $b.Status -eq 'Running') } ");
            script.append("} catch { $r.code=-1; $r.error=$stage; $stage | Set-Content -LiteralPath (Join-Path $d 'setup-error.txt') -Encoding UTF8 }; $r | ConvertTo-Json -Compress | Set-Content -LiteralPath $o -Encoding UTF8; $r | ConvertTo-Json -Compress");
            return script.str;
        }
        private string validate_artifact(GuestToolsArtifact artifact) throws Error {
            if (artifact.iso || !Regex.match_simple("\\A[0-9a-fA-F]{64}\\z", artifact.sha256)) throw new IOError.INVALID_ARGUMENT("Select a verified Windows executable installer.");
            var input = File.new_for_path(artifact.path).read();
            var checksum = new Checksum(ChecksumType.SHA256);
            uint8[] buffer = new uint8[65536];
            int64 total = 0; bool mz = false;
            try {
                ssize_t count;
                while ((count = input.read(buffer)) > 0) {
                    if (total == 0) mz = count >= 2 && buffer[0] == 'M' && buffer[1] == 'Z';
                    total += count;
                    if (total > 256 * 1024 * 1024) throw new IOError.INVALID_DATA("Installer exceeds size limit.");
                    checksum.update(buffer, (size_t)count);
                }
            } finally { try { input.close(); } catch (Error e) {} }
            if (!mz || checksum.get_string() != artifact.sha256.down()) throw new IOError.INVALID_DATA("Installer executable or SHA256 verification failed.");
            return checksum.get_string();
        }
        private int64 open(VmModel vm, string path, string mode) throws Error {
            var args = new Json.Object(); args.set_string_member("path", path); args.set_string_member("mode", mode);
            var value = agent.command(vm, "guest-file-open", args);
            if (value.get_node_type() != Json.NodeType.VALUE || value.get_value_type() != typeof(int64) || value.get_int() < 0)
                throw new IOError.INVALID_DATA("Malformed guest file handle.");
            return value.get_int();
        }
        private void close(VmModel vm, int64 handle) throws Error {
            var args = new Json.Object(); args.set_int_member("handle", handle); agent.command(vm, "guest-file-close", args);
        }
        private void upload(VmModel vm, string path, string destination) throws Error {
            var input = File.new_for_path(path).read();
            int64 handle = -1;
            Error? cleanup_error = null;
            try {
                handle = open(vm, destination, "wb");
                uint8[] bytes = new uint8[65536]; ssize_t count; int64 total = 0;
                while ((count = input.read(bytes)) > 0) {
                    total += count;
                    if (total > 256 * 1024 * 1024) throw new IOError.INVALID_DATA("Installer exceeds upload size limit.");
                    var args = new Json.Object(); args.set_int_member("handle", handle);
                    args.set_string_member("buf-b64", Base64.encode(bytes[0:(int)count]));
                    if (number(call(vm, "guest-file-write", args), "count") != count) throw new IOError.FAILED("Guest installer upload was incomplete.");
                }
            } finally {
                try { input.close(); } catch (Error e) { cleanup_error = e; }
                if (handle >= 0) { try { close(vm, handle); } catch (Error e) { cleanup_error = e; } }
            }
            if (cleanup_error != null) throw cleanup_error;
        }
        private Json.Object read_outcome(VmModel vm, string directory) throws Error {
            int64 handle = open(vm, directory + "\\outcome.json", "r");
            try {
                var args = new Json.Object(); args.set_int_member("handle", handle); args.set_int_member("count", 16384);
                var reply = call(vm, "guest-file-read", args);
                int64 count = number(reply, "count");
                string text = decode(str(reply, "buf-b64"));
                if (count != text.length || count >= 16384) throw new IOError.INVALID_DATA("Malformed guest outcome size.");
                if (text.has_prefix("\xef\xbb\xbf")) text = text.substring(3);
                var parser = new Json.Parser(); parser.load_from_data(text); return object_node(parser.get_root());
            } finally { try { close(vm, handle); } catch (Error e) {} }
        }
        private void journal(string path, string key, string phase, string directory, int64 pid, GuestToolsArtifact artifact, GuestInstallResult result) throws Error {
            var obj = new Json.Object();
            obj.set_string_member("resource_key", key); obj.set_string_member("phase", phase);
            obj.set_string_member("remote_directory", directory); obj.set_int_member("pid", pid);
            obj.set_string_member("package_version", artifact.version); obj.set_string_member("sha256", artifact.sha256);
            obj.set_string_member("summary", result.summary); obj.set_int_member("exit_code", result.exit_code);
            obj.set_int_member("state", (int)result.state);
            var node = new Json.Node(Json.NodeType.OBJECT); node.set_object(obj);
            var generator = new Json.Generator(); generator.set_root(node);
            string contents = generator.to_data(null);
            string? new_etag;
            File.new_for_path(path).replace_contents(contents.data, null, false, FileCreateFlags.PRIVATE, out new_etag);
        }
        private static string resource_key(VmModel vm) {
            string identity;
            if (vm.vm_type == "libvirt") identity = string.joinv("|", { "libvirt", vm.connection_uri, vm.resource_id.down() });
            else {
                string socket = Posix.realpath(vm.guest_agent_socket) ?? File.new_for_path(vm.guest_agent_socket).get_path();
                identity = "qga-socket|" + socket;
            }
            return Checksum.compute_for_string(ChecksumType.SHA256, identity);
        }
        private static void parse_outcome(Json.Object outcome, GuestInstallResult result) throws Error {
            int64 code = number(outcome, "code");
            if (code < int.MIN || code > int.MAX) throw new IOError.INVALID_DATA("Guest installer exit code is outside the supported range.");
            bool service = flag(outcome, "service"); bool requires_reboot = flag(outcome, "reboot");
            result.exit_code = (int)code;
            if (code == 3010 && requires_reboot) { result.state = GuestInstallState.REBOOT_REQUIRED; result.summary = _("Drivers installed. Restart Windows to finish setup."); }
            else if (code == 0 && service && !requires_reboot) { result.state = GuestInstallState.SUCCEEDED; result.summary = _("Drivers installed and BalloonService is running."); }
            else { result.state = GuestInstallState.FAILED; result.summary = code == 1641 ? _("The installer unexpectedly started a restart. Verify Windows and driver status.") : _("Driver installation or BalloonService verification failed. Check the guest installation log."); }
            if (result.state == GuestInstallState.FAILED && outcome.has_member("error")) {
                string reason = str(outcome, "error");
                if (reason.length > 64) throw new IOError.INVALID_DATA("Guest installer error label is too long.");
                switch (reason) {
                    case "hash": result.summary = _("Guest installer SHA256 verification failed. The installer was not started."); break;
                    case "signature": result.summary = _("Windows could not validate the installer signature. The installer was not started."); break;
                    case "signer": result.summary = _("The installer is not signed by the expected Red Hat publisher. The installer was not started."); break;
                    case "installer": result.summary = _("Windows could not complete the driver installer. Check the guest setup-error.txt and install.log files."); break;
                }
            }
        }
        private static string bounded_file(string path, int limit) throws Error {
            var stream = File.new_for_path(path).read();
            try {
                uint8[] bytes = new uint8[limit + 1]; size_t count;
                stream.read_all(bytes, out count);
                if (count > limit) throw new IOError.INVALID_DATA("Installation journal exceeds size limit.");
                bytes[count] = 0;
                string text = (string)bytes;
                if (text.length != count || !text.validate()) throw new IOError.INVALID_DATA("Invalid installation journal text.");
                return text;
            } finally { try { stream.close(); } catch (Error e) {} }
        }
        public bool has_pending(VmModel vm) {
            return FileUtils.test(Path.build_filename(state_dir, resource_key(vm) + ".active"), FileTest.IS_REGULAR);
        }
        public GuestInstallResult resume(VmModel vm, uint timeout_ms = 5000) throws Error {
            string key = resource_key(vm);
            string marker = Path.build_filename(state_dir, key + ".active");
            active_mutex.lock();
            if (active == null) active = new HashTable<string, bool>(str_hash, str_equal);
            if (active.contains(key)) { active_mutex.unlock(); throw new IOError.BUSY("Driver installation is still active in Rigs."); }
            active.insert(key, true); active_mutex.unlock();
            try {
                string job = bounded_file(marker, 64);
                if (!Regex.match_simple("\\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\z", job))
                    throw new IOError.INVALID_DATA("Invalid installation job marker.");
                var result = new GuestInstallResult();
                result.journal_path = Path.build_filename(state_dir, job + ".json");
                result.remote_directory = "C:\\ProgramData\\Rigs\\GuestTools\\" + job;
                var parser = new Json.Parser(); parser.load_from_data(bounded_file(result.journal_path, 16384));
                var record = object_node(parser.get_root());
                string sha = str(record, "sha256");
                string phase = str(record, "phase");
                int64 pid = number(record, "pid");
                if (str(record, "resource_key") != key || str(record, "remote_directory") != result.remote_directory ||
                    !Regex.match_simple("\\A[0-9a-fA-F]{64}\\z", sha) || pid < -1 || pid > int.MAX ||
                    (phase != "preflight" && phase != "upload" && phase != "launching" && phase != "installing" && phase != "pending" && phase != "finished"))
                    throw new IOError.INVALID_DATA("Invalid installation journal identity.");
                var artifact = new GuestToolsArtifact("", sha, str(record, "package_version"));
                int64 end = get_monotonic_time() + (int64)timeout_ms * 1000;
                Json.Object? outcome = null;
                do {
                    // The durable outcome takes priority after an agent restart.
                    try { outcome = read_outcome(vm, result.remote_directory); } catch (Error e) {}
                    if (outcome == null && pid > 0) { try { outcome = status(vm, pid); } catch (Error e) {} }
                    if (outcome != null) break;
                    if (get_monotonic_time() >= end) break;
                    pause();
                } while (get_monotonic_time() < end);
                if (outcome == null) {
                    result.state = GuestInstallState.TIMED_OUT;
                    result.summary = _("Installation status is unknown. Check the guest installation log before retrying.");
                    journal(result.journal_path, key, "pending", result.remote_directory, pid, artifact, result);
                } else {
                    parse_outcome(outcome, result);
                    journal(result.journal_path, key, "finished", result.remote_directory, pid, artifact, result);
                    File.new_for_path(marker).delete();
                }
                return result;
            } finally { active_mutex.lock(); active.remove(key); active_mutex.unlock(); }
        }
        public GuestInstallResult install(VmModel vm, GuestToolsArtifact artifact, uint timeout_ms = 600000) throws Error {
            string key = resource_key(vm);
            active_mutex.lock();
            if (active == null) active = new HashTable<string, bool>(str_hash, str_equal);
            if (active.contains(key)) { active_mutex.unlock(); throw new IOError.BUSY("A driver installation is already active for this guest."); }
            active.insert(key, true); active_mutex.unlock();
            var result = new GuestInstallResult(); int64 pid = -1;
            string lock_path = Path.build_filename(state_dir, key + ".active");
            bool owns_lock = false;
            bool uncertain = false;
            string job = Uuid.string_random();
            result.remote_directory = "C:\\ProgramData\\Rigs\\GuestTools\\" + job;
            try {
                if (DirUtils.create_with_parents(state_dir, 0700) != 0) throw new IOError.FAILED("Cannot create driver installation journal directory.");
                FileUtils.chmod(state_dir, 0700);
                FileOutputStream lock_stream;
                try { lock_stream = File.new_for_path(lock_path).create(FileCreateFlags.PRIVATE); }
                catch (IOError.EXISTS e) { throw new IOError.BUSY("An earlier driver installation may still be running. Review its guest log and host journal before retrying."); }
                owns_lock = true;
                Error? lock_close_error = null;
                try { size_t written; lock_stream.write_all(job.data, out written); }
                finally { try { lock_stream.close(); } catch (Error e) { lock_close_error = e; } }
                if (lock_close_error != null) throw lock_close_error;
                result.journal_path = Path.build_filename(state_dir, job + ".json");
                journal(result.journal_path, key, "preflight", result.remote_directory, pid, artifact, result);
                progress(_("Checking Windows guest and installer…"));
                var check = probe(vm);
                if (!check.available || !check.compatible || !check.administrator) { result.summary = check.summary; return result; }
                string hash = validate_artifact(artifact);
                pid = execute(vm, "$ErrorActionPreference='Stop'; New-Item -ItemType Directory -Path " + quote(result.remote_directory) + " -Force | Out-Null; @{created=$true} | ConvertTo-Json -Compress");
                int64 end = get_monotonic_time() + (int64)timeout_ms * 1000;
                bool created = false;
                while (get_monotonic_time() < end) { var data = status(vm, pid); if (data != null) { created = flag(data, "created"); break; } pause(); }
                if (!created) throw new IOError.TIMED_OUT("Guest installation directory creation timed out.");
                progress(_("Uploading verified driver installer…"));
                journal(result.journal_path, key, "upload", result.remote_directory, pid, artifact, result);
                upload(vm, artifact.path, result.remote_directory + "\\guest-tools.exe");
                progress(_("Installing Windows guest drivers…"));
                // Record intent before launch: reconnects may lose the guest-exec reply.
                journal(result.journal_path, key, "launching", result.remote_directory, -1, artifact, result);
                uncertain = true;
                try { pid = execute(vm, install_script(result.remote_directory, hash)); } catch (Error e) { pid = -1; }
                journal(result.journal_path, key, "installing", result.remote_directory, pid, artifact, result);
                end = get_monotonic_time() + (int64)timeout_ms * 1000;
                Json.Object? outcome = null;
                while (get_monotonic_time() < end) {
                    try { if (pid > 0) outcome = status(vm, pid); } catch (Error e) {}
                    if (outcome == null) { try { outcome = read_outcome(vm, result.remote_directory); } catch (Error e) {} }
                    if (outcome != null) break;
                    pause();
                }
                if (outcome == null) { result.state = GuestInstallState.TIMED_OUT; result.summary = _("Installation status is unknown. Check the guest installation log before retrying."); }
                else {
                    parse_outcome(outcome, result);
                    uncertain = false;
                }
                return result;
            } catch (Error e) {
                if (uncertain) {
                    result.state = GuestInstallState.TIMED_OUT;
                    result.summary = _("Installation status is unknown. Check the guest installation log before retrying.");
                } else result.summary = _("Driver setup failed before a verified outcome. Check the installation journal.");
                throw e;
            } finally {
                if (result.journal_path.length > 0) {
                    try { journal(result.journal_path, key, "finished", result.remote_directory, pid, artifact, result); } catch (Error e) { warning("Cannot update driver installation journal."); }
                }
                // Unknown jobs may still be running in Windows. Preserve their durable
                // marker so a restart of Rigs cannot accidentally start a second job.
                if (owns_lock && !uncertain) {
                    try { File.new_for_path(lock_path).delete(); } catch (Error e) { warning("Cannot remove completed driver installation marker."); }
                }
                active_mutex.lock(); active.remove(key); active_mutex.unlock();
            }
        }
        public void reboot(VmModel vm) throws Error { agent.reboot(vm); }
    }
}
