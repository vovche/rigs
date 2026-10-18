using Rigs;
namespace Rigs.Tests {
    private class TestPackages : GuestToolsPackages {
        private uint8[] bytes;
        public bool tamper = false;
        public int downloads = 0;
        public TestPackages(string dir, uint8[] bytes) { base(dir); this.bytes = bytes; }
        protected override string expected_hash(bool iso) { return Checksum.compute_for_data(ChecksumType.SHA256, bytes); }
        protected override InputStream download(string uri, Cancellable? cancel, out int64 length) throws Error {
            assert(uri == GuestToolsPackages.SOURCE + "virtio-win-guest-tools.exe");
            downloads++;
            uint8[] response = tamper ? new uint8[] {'M','Z',9} : bytes;
            length = response.length;
            return new MemoryInputStream.from_bytes(new Bytes(response));
        }
    }
    public class TestGuestToolsPackages {
        public static void test_download() {
            try {
                string dir = DirUtils.make_tmp("rigs-packages-XXXXXX");
                uint8[] bytes = {'M','Z',0,1,2,3};
                var packages = new TestPackages(dir, bytes);
                var canceled = new Cancellable();
                canceled.cancel();
                try { packages.fetch(false, canceled); assert_not_reached(); }
                catch (Error e) { assert(e is IOError.CANCELLED); }
                assert(packages.downloads == 0);
                var artifact = packages.fetch(false);
                assert(artifact.sha256 == Checksum.compute_for_data(ChecksumType.SHA256, bytes));
                assert(artifact.version == GuestToolsPackages.VERSION);
                assert(packages.downloads == 1);
                packages.fetch(false);
                assert(packages.downloads == 1);
                FileUtils.set_contents(artifact.path, "corrupted cache");
                packages.fetch(false);
                assert(packages.downloads == 2);
                FileUtils.unlink(artifact.path);
                packages.tamper = true;
                try { packages.fetch(false); assert_not_reached(); } catch (Error e) { assert(e is IOError.INVALID_DATA); }
                assert(!FileUtils.test(artifact.path, FileTest.EXISTS));
                var directory = Dir.open(dir);
                assert(directory.read_name() == null); // No partial files survive verification failure.
                DirUtils.remove(dir);
            } catch (Error e) { assert_not_reached(); }
        }
        public static void test_local_files() {
            try {
                string dir = DirUtils.make_tmp("rigs-package-file-XXXXXX");
                string path = Path.build_filename(dir, "installer.exe");
                FileUtils.set_contents(path, "MZfixture");
                var artifact = GuestToolsPackages.local_file(path, false);
                assert(artifact.version.length > 0 && artifact.sha256.length == 64);
                try { GuestToolsPackages.local_file(path, false, string.nfill(64, '0')); assert_not_reached(); }
                catch (Error e) { assert(e is IOError.INVALID_DATA); }
                FileUtils.set_contents(path, "<html>download failed</html>");
                try { GuestToolsPackages.local_file(path, false); assert_not_reached(); }
                catch (Error e) { assert(e is IOError.INVALID_DATA); }
                FileUtils.unlink(path); DirUtils.remove(dir);
            } catch (Error e) { assert_not_reached(); }
        }
    }
}
