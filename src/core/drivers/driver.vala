/* driver.vala — one implementation per ResourceKind (see DriverRegistry).
 *
 * Every method BLOCKS: it runs host commands or talks to sockets. Call drivers only
 * through ResourceActions (worker thread + publishing) or from the monitor thread.
 * A failure is RETURNED as a ResourceIssue, never logged: lint SILENT-01/02.
 * Return null when the operation succeeded. */
namespace Rigs {
    public interface Driver : Object {
        public abstract ResourceKind kind { get; }
        public abstract ResourceIssue? start(Resource resource);
        public abstract ResourceIssue? stop(Resource resource);
        // Opens the user's console/viewer (connect_cmd, virt-viewer).
        public abstract ResourceIssue? open_console(Resource resource);
        public abstract ResourceIssue? insert_iso(Resource resource, string iso_path);
        public abstract ResourceIssue? eject_iso(Resource resource);
        // Called every 1–3 s from the monitor thread; must stay cheap and bounded.
        public abstract ResourceStatus check_status(Resource resource);
    }
}
