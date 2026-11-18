namespace Rigs.Tests {
    private class InstallerAgent : GuestAgent {
        public bool supported = true;
        public bool malformed = false;
        public bool partial = false;
        public bool reconnect = false;
        public bool never_finishes = false;
        public int64 code = 0;
        public bool service = true;
        public uint mutations = 0;
        public uint reboots = 0;
        private int64 next_pid = 0;
        private static Json.Node parse(string text) throws Error {
            var p = new Json.Parser(); p.load_from_data(text); return p.get_root().copy();
        }
        private string outcome() { return "{\"code\":" + code.to_string() + ",\"reboot\":" + (code == 3010 ? "true" : "false") + ",\"service\":" + (service ? "true" : "false") + "}"; }
        public override Json.Node command(Resource resource, string name, Json.Object? args = null, uint timeout_ms = 5000) throws Error {
            Test.message("Fake guest operation: %s", name);
            switch (name) {
                case "guest-info":
                    var list = new Json.Array();
                    foreach (string command in new string[] { "guest-get-osinfo", "guest-exec", "guest-exec-status", "guest-file-open", "guest-file-write", "guest-file-read", "guest-file-close" }) {
                        var entry = new Json.Object(); entry.set_string_member("name", command); entry.set_boolean_member("enabled", supported); list.add_object_element(entry);
                    }
                    var info = new Json.Object(); info.set_array_member("supported_commands", list);
                    var node = new Json.Node(Json.NodeType.OBJECT); node.set_object(info); return node;
                case "guest-get-osinfo": return parse("{\"id\":\"mswindows\",\"machine\":\"x86_64\",\"version-id\":\"10\"}");
                case "guest-exec":
                    assert(args.get_string_member("path") == "powershell.exe");
                    assert(args.get_array_member("arg").get_string_element(2) == "-EncodedCommand");
                    next_pid++;
                    if (next_pid > 1) mutations++;
                    return parse("{\"pid\":" + next_pid.to_string() + "}");
                case "guest-exec-status":
                    int64 pid = args.get_int_member("pid");
                    if (pid == 3 && reconnect) throw new IOError.NOT_FOUND("PID lost on reconnect");
                    if (pid == 3 && never_finishes) return parse("{\"exited\":false}");
                    string output;
                    if (pid == 1) output = "{\"administrator\":true,\"balloon_service_running\":false}";
                    else if (pid == 2) output = "{\"created\":true}";
                    else output = outcome();
                    if (malformed && pid == 1) output = "{\"administrator\":1}";
                    return parse("{\"exited\":true,\"exitcode\":0,\"out-data\":\"" + Base64.encode(output.data) + "\"}");
                case "guest-file-open":
                    if (args.get_string_member("mode") == "wb") mutations++;
                    else if (never_finishes) throw new IOError.NOT_FOUND("No outcome yet");
                    return parse("12");
                case "guest-file-write":
                    mutations++;
                    var bytes = Base64.decode(args.get_string_member("buf-b64"));
                    return parse("{\"count\":" + (partial ? 1 : bytes.length).to_string() + "}");
                case "guest-file-read":
                    string data = outcome();
                    return parse("{\"count\":" + data.length.to_string() + ",\"buf-b64\":\"" + Base64.encode(data.data) + "\"}");
                case "guest-file-close": return parse("{}");
            }
            assert_not_reached();
        }
        public override void reboot(Resource resource) throws Error { reboots++; }
    }
    public class TestWindowsGuestInstaller {
        private static GuestToolsArtifact fixture(string directory) throws Error {
            string path = Path.build_filename(directory, "installer.exe");
            FileUtils.set_contents(path, "MZfake-signed-package");
            return new GuestToolsArtifact(path, Checksum.compute_for_string(ChecksumType.SHA256, "MZfake-signed-package"), "test");
        }
        public static void test_probe() {
            try {
                var agent = new InstallerAgent();
                var installer = new WindowsGuestInstaller(agent, DirUtils.make_tmp("rigs-installer-probe-XXXXXX"));
                var probe = installer.probe(new Resource());
                assert(probe.available && probe.compatible && probe.administrator && !probe.balloon_service_running);
                assert(agent.mutations == 0);
                agent.supported = false;
                assert(!installer.probe(new Resource()).available && agent.mutations == 0);
            } catch (Error e) { error("Probe test: %s", e.message); }
        }
        public static void test_install() {
            try {
                foreach (int code in new int[] { 0, 3010 }) {
                    string dir = DirUtils.make_tmp("rigs-installer-install-XXXXXX");
                    var agent = new InstallerAgent(); agent.code = code; agent.reconnect = code == 3010;
                    var installer = new WindowsGuestInstaller(agent, dir); installer.poll_interval_ms = 0;
                    var result = installer.install(new Resource(), fixture(dir), 50);
                    assert(result.state == (code == 0 ? GuestInstallState.SUCCEEDED : GuestInstallState.REBOOT_REQUIRED));
                    assert(result.exit_code == code && agent.reboots == 0);
                    assert(FileUtils.test(result.journal_path, FileTest.IS_REGULAR));
                    string journal; FileUtils.get_contents(result.journal_path, out journal);
                    assert(journal.contains("finished") && journal.contains("sha256") && !journal.contains("MZfake"));
                }
            } catch (Error e) { error("Install test: %s", e.message); }
        }
        public static void test_failures() {
            try {
                string dir = DirUtils.make_tmp("rigs-installer-failure-XXXXXX");
                var artifact = fixture(dir);
                var resource = new Resource();
                var unsupported = new InstallerAgent(); unsupported.supported = false;
                assert(new WindowsGuestInstaller(unsupported, dir).install(resource, artifact, 1).state == GuestInstallState.FAILED);
                assert(unsupported.mutations == 0);
                var invalid = new InstallerAgent();
                artifact.sha256 = string.nfill(64, '0');
                bool rejected = false;
                try { new WindowsGuestInstaller(invalid, dir).install(resource, artifact, 1); } catch (Error e) { rejected = true; }
                assert(rejected && invalid.mutations == 0);
                artifact = fixture(dir);
                artifact.sha256 += "\n"; rejected = false;
                var newline_hash = new InstallerAgent();
                try { new WindowsGuestInstaller(newline_hash, dir).install(resource, artifact, 1); } catch (Error e) { rejected = true; }
                assert(rejected && newline_hash.mutations == 0);
                artifact = fixture(dir);
                var partial = new InstallerAgent(); partial.partial = true; rejected = false;
                try { new WindowsGuestInstaller(partial, dir).install(resource, artifact, 50); } catch (Error e) { rejected = true; }
                assert(rejected && partial.reboots == 0);
                var bad = new InstallerAgent(); bad.malformed = true; rejected = false;
                try { new WindowsGuestInstaller(bad, dir).probe(resource); } catch (Error e) { rejected = true; }
                assert(rejected && bad.mutations == 0);
                var unsigned = new InstallerAgent(); unsigned.code = -1; unsigned.service = false;
                assert(new WindowsGuestInstaller(unsigned, dir).install(resource, artifact, 50).state == GuestInstallState.FAILED);
                var timeout = new InstallerAgent(); timeout.never_finishes = true;
                var installer = new WindowsGuestInstaller(timeout, dir); installer.poll_interval_ms = 0;
                assert(installer.install(resource, artifact, 1).state == GuestInstallState.TIMED_OUT && timeout.reboots == 0);
            } catch (Error e) { error("Failure test: %s", e.message); }
        }
        public static void test_scripts() {
            string script = WindowsGuestInstaller.install_script("C:\\ProgramData\\Rigs\\GuestTools\\test", string.nfill(64, 'a'));
            assert(script.index_of("Get-FileHash") < script.index_of("Start-Process"));
            assert(script.index_of("Get-AuthenticodeSignature") < script.index_of("Start-Process"));
            assert(script.contains("-cnotcontains") && script.contains("Status -ne 'Valid'"));
            assert(script.contains("/norestart") && script.contains("outcome.json"));
            assert(!script.contains("ExecutionPolicy") && !script.contains("Import-Certificate"));
            assert(!WindowsGuestInstaller.preflight_script().contains("Start-Process"));
        }
        public static void test_resume() {
            try {
                string dir = DirUtils.make_tmp("rigs-installer-resume-XXXXXX");
                var resource = new Resource(); resource.id = "resume-test"; resource.guest_agent_socket = Path.build_filename(dir, "agent.sock");
                var timeout = new InstallerAgent(); timeout.never_finishes = true;
                var installer = new WindowsGuestInstaller(timeout, dir); installer.poll_interval_ms = 0;
                assert(installer.install(resource, fixture(dir), 1).state == GuestInstallState.TIMED_OUT);
                assert(installer.has_pending(resource));
                var alias = new Resource(); alias.id = "other-card-for-same-guest";
                alias.guest_agent_socket = Path.build_filename(dir, ".", "agent.sock");
                assert(installer.has_pending(alias));
                var waiting = new InstallerAgent(); waiting.never_finishes = true; waiting.reconnect = true;
                var resumed = new WindowsGuestInstaller(waiting, dir); resumed.poll_interval_ms = 0;
                assert(resumed.resume(resource, 1).state == GuestInstallState.TIMED_OUT);
                assert(resumed.has_pending(resource) && waiting.mutations == 0 && waiting.reboots == 0);
                var overflow = new InstallerAgent(); overflow.code = int64.MAX;
                bool rejected = false;
                try { new WindowsGuestInstaller(overflow, dir).resume(resource, 1); } catch (Error e) { rejected = true; }
                assert(rejected && resumed.has_pending(resource));
                var ready = new InstallerAgent(); ready.code = 3010;
                var checker = new WindowsGuestInstaller(ready, dir);
                var result = checker.resume(resource, 1);
                assert(result.state == GuestInstallState.REBOOT_REQUIRED && !checker.has_pending(resource));
                assert(ready.mutations == 0 && ready.reboots == 0);
                string journal; FileUtils.get_contents(result.journal_path, out journal);
                assert(journal.contains("finished"));
            } catch (Error e) { error("Resume test: %s", e.message); }
        }
    }
}
