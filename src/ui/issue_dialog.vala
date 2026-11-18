using GLib.Intl;

/* issue_dialog.vala — explains why a resource failed to start. */
namespace Rigs {
    public class IssueDialog : Adw.AlertDialog {
        public IssueDialog(Resource resource, ResourceIssue issue) {
            Object(heading: ResourceIssue.headline(issue.operation, resource.name), body: issue.title);
            this.body_use_markup = false;
            this.add_response("close", _("Close"));
            this.default_response = "close";
            this.close_response = "close";

            var box = new Gtk.Box(Gtk.Orientation.VERTICAL, 12);

            var description = new Gtk.Label(issue.description);
            description.wrap = true;
            description.xalign = 0;
            box.append(description);

            if (issue.suggested_action != null && issue.suggested_action.length > 0) {
                var action = new Gtk.Label(issue.suggested_action);
                action.wrap = true;
                action.xalign = 0;
                action.add_css_class("dim-label");
                box.append(action);
            }

            if (issue.suggested_command != null && issue.suggested_command.length > 0) {
                string command = issue.suggested_command;
                var row = new Gtk.Box(Gtk.Orientation.HORIZONTAL, 6);
                var code = new Gtk.Label(command);
                code.selectable = true;
                code.wrap = true;
                code.xalign = 0;
                code.hexpand = true;
                code.add_css_class("monospace");
                code.add_css_class("card");
                code.margin_top = code.margin_bottom = 4;
                row.append(code);
                var copy = new Gtk.Button.with_label(_("Copy"));
                copy.valign = Gtk.Align.CENTER;
                copy.clicked.connect(() => {
                    copy.get_clipboard().set_text(command);
                    copy.label = _("Copied");
                });
                row.append(copy);
                box.append(row);
            }

            if (issue.matched_snippet != null && issue.matched_snippet.length > 0) {
                var raw = new Gtk.Label(issue.matched_snippet);
                raw.selectable = true;
                raw.wrap = true;
                raw.wrap_mode = Pango.WrapMode.CHAR;
                raw.xalign = 0;
                raw.add_css_class("monospace");
                var scroll = new Gtk.ScrolledWindow();
                scroll.set_child(raw);
                scroll.max_content_height = 120;
                scroll.propagate_natural_height = true;
                scroll.hscrollbar_policy = Gtk.PolicyType.NEVER;
                var expander = new Gtk.Expander(_("Raw output"));
                expander.set_child(scroll);
                box.append(expander);
            }

            this.set_extra_child(box);
        }
    }
}
