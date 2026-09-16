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

    var app = new Rigs.Application();
    return app.run(args);
}
