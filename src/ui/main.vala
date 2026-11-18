/* main.vala — Application entrypoint for Rigs */

using GLib.Intl;

int main(string[] args) {
    Intl.setlocale(LocaleCategory.ALL, "");
    Intl.bindtextdomain(Rigs.Config.GETTEXT_PACKAGE, Rigs.Config.LOCALEDIR);

    string user_localedir = Path.build_filename(Environment.get_user_data_dir(), "locale");
    if (FileUtils.test(user_localedir, FileTest.IS_DIR)) {
        Intl.bindtextdomain(Rigs.Config.GETTEXT_PACKAGE, user_localedir);
    }

    Intl.bind_textdomain_codeset(Rigs.Config.GETTEXT_PACKAGE, "UTF-8");
    Intl.textdomain(Rigs.Config.GETTEXT_PACKAGE);

    for (int i = 1; i < args.length; i++) {
        if (args[i] == "--debug-info" || args[i] == "-d" || args[i] == "--diagnostics") {
            print("%s", Rigs.SystemDiagnostics.get_report(Rigs.Application.toolkit_versions()));
            return 0;
        } else if (args[i] == "--version" || args[i] == "-v") {
            print("Rigs %s\n", Rigs.Config.VERSION);
            return 0;
        }
    }

    var app = new Rigs.Application();
    return app.run(args);
}
