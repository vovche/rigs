rigs_sources = [
  'main.vala',
  'application.vala',
  'window.vala',
  'vm_card.vala',
  'add_dialog.vala',
  'vm_model.vala',
  'monitor.vala',
]

executable('rigs',
  rigs_sources,
  resources,
  dependencies: [
    gtk_dep,
    adw_dep,
    json_dep,
    glib_dep,
    gio_dep,
    posix_dep,
  ],
  install: true,
)
