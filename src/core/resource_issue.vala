using GLib.Intl;

/* resource_issue.vala — a failure the user must see: what went wrong, why, and what to do.
 * Drivers return one (never log it); ResourceActions publishes it on the Resource;
 * the UI shows a toast, a warning icon on the card and IssueDialog. */
namespace Rigs {
    public enum FailureCategory {
        STORAGE_MOUNT,
        NETWORK_PORT,
        CONTAINER_CONFLICT,
        PERMISSIONS_KVM,
        RESOURCE_EXHAUSTION,
        MISSING_PROGRAM,
        TIMEOUT,
        UNSUPPORTED,
        GENERIC_ERROR
    }

    // What the user asked for when the failure happened; selects the headline wording.
    public enum ResourceOperation {
        START,
        STOP,
        CONNECT,
        MEDIA,
        // The resource was running and its start command exited with an error later.
        RUN
    }

    public class ResourceIssue : Object {
        public FailureCategory category { get; set; default = FailureCategory.GENERIC_ERROR; }
        // Set by ResourceActions from the requested operation (drivers set only RUN).
        public ResourceOperation operation { get; set; default = ResourceOperation.START; }
        public string title { get; set; default = ""; }
        public string description { get; set; default = ""; }
        // Human-readable advice (may mention a command in backticks).
        public string? suggested_action { get; set; default = null; }
        // Copy-pasteable shell command, only when one is safe and specific.
        public string? suggested_command { get; set; default = null; }
        // The output line(s) the diagnosis is based on.
        public string? matched_snippet { get; set; default = null; }

        public ResourceIssue(FailureCategory category, string title, string description,
                string? action = null, string? command = null, string? snippet = null) {
            this.category = category;
            this.title = title;
            this.description = description;
            this.suggested_action = action;
            this.suggested_command = command;
            this.matched_snippet = snippet;
        }

        // One headline per operation, shared by the toast, the card tooltip and the dialog.
        public static string headline(ResourceOperation operation, string name) {
            switch (operation) {
                case ResourceOperation.STOP: return _("Failed to stop %s").printf(name);
                case ResourceOperation.CONNECT: return _("Could not connect to %s").printf(name);
                case ResourceOperation.MEDIA: return _("Could not change the optical media of %s").printf(name);
                case ResourceOperation.RUN: return _("%s stopped with an error").printf(name);
                default: return _("Failed to start %s").printf(name);
            }
        }

        // An exception from HostCommand/GIO (program missing, timeout, unsupported package).
        public static ResourceIssue from_error(Error e) {
            if (e.matches(IOError.quark(), IOError.TIMED_OUT))
                return new ResourceIssue(FailureCategory.TIMEOUT, _("The command timed out"),
                    _("The command did not finish within its time limit."),
                    _("Run the command in a terminal to see where it stops."), null, e.message);
            if (e.matches(SpawnError.quark(), SpawnError.NOENT) || e.matches(IOError.quark(), IOError.NOT_FOUND))
                return new ResourceIssue(FailureCategory.MISSING_PROGRAM, _("Program not found"),
                    _("A program this resource needs is not installed or not in PATH."),
                    _("Install the missing program or fix the command in the resource settings."), null, e.message);
            if (e.matches(IOError.quark(), IOError.NOT_SUPPORTED))
                return unsupported(e.message);
            return new ResourceIssue(FailureCategory.GENERIC_ERROR, _("The operation failed"),
                _("Rigs could not run the command for this resource."),
                _("Check the output below for details."), null, e.message);
        }

        // The resource or this installation cannot do what was asked.
        public static ResourceIssue unsupported(string reason) {
            return new ResourceIssue(FailureCategory.UNSUPPORTED, _("Not supported"), reason);
        }

        // The command finished without an error, yet the resource is not running.
        public static ResourceIssue not_running(string detail, string? suggested_command = null) {
            return new ResourceIssue(FailureCategory.GENERIC_ERROR, _("The resource stopped right after start"),
                _("The start command finished, but the resource is not running."),
                suggested_command != null ? _("Inspect it with `%s`.").printf(suggested_command)
                                          : _("Check the output below for details."),
                suggested_command, detail);
        }
    }
}
