/* resource_actions.vala — the only place driver operations run off the main thread.
 *
 * UI → ResourceActions.start(resource) → worker thread → Driver.start() → ResourceIssue?
 *    → (main loop) resource.last_issue + resource.issue_raised → toast, card icon, dialog.
 * Because drivers RETURN their failure, no driver can forget to report one. */
namespace Rigs {
    public class ResourceActions : Object {
        public delegate ResourceIssue? Operation(Driver driver);

        private DriverRegistry registry;

        public ResourceActions(DriverRegistry? registry = null) {
            this.registry = registry ?? DriverRegistry.get_default();
        }

        public void start(Resource resource) {
            resource.last_issue = null;
            run(resource, ResourceOperation.START, (d) => d.start(resource));
        }

        public void stop(Resource resource) {
            resource.last_issue = null;
            run(resource, ResourceOperation.STOP, (d) => d.stop(resource));
        }

        public void open_console(Resource resource) {
            run(resource, ResourceOperation.CONNECT, (d) => d.open_console(resource));
        }

        public void insert_iso(Resource resource, string iso_path) {
            run(resource, ResourceOperation.MEDIA, (d) => d.insert_iso(resource, iso_path));
        }

        public void eject_iso(Resource resource) {
            run(resource, ResourceOperation.MEDIA, (d) => d.eject_iso(resource));
        }

        // Synchronous core of every action; public for headless tests.
        public ResourceIssue? run_blocking(Resource resource, ResourceOperation operation, Operation call) {
            Driver? driver = registry.get_driver(resource.kind);
            ResourceIssue? issue = driver != null ? call(driver)
                : ResourceIssue.unsupported("No driver handles resources of type “%s”.".printf(resource.kind.to_id()));
            // Drivers only mark late crashes (RUN); everything else is the requested operation.
            if (issue != null && issue.operation != ResourceOperation.RUN) issue.operation = operation;
            return issue;
        }

        private void run(Resource resource, ResourceOperation operation, owned Operation call) {
            new Thread<void*>("rigs-action", () => {
                var issue = run_blocking(resource, operation, call);
                if (issue != null) publish(resource, issue);
                return null;
            });
        }

        // Safe from worker threads: the model changes on the main context.
        public static void publish(Resource resource, ResourceIssue issue) {
            Idle.add(() => {
                resource.last_issue = issue;
                resource.issue_raised(issue);
                return Source.REMOVE;
            });
        }
    }
}
