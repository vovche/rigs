gnome = import('gnome')

resources = gnome.compile_resources(
  'rigs-resources',
  'rigs.gresource.xml',
  source_dir: '.',
  c_name: 'rigs'
)

install_data(
  'io.github.vovche.Rigs.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data(
  'io.github.vovche.Rigs.metainfo.xml.in',
  rename: 'io.github.vovche.Rigs.metainfo.xml',
  install_dir: get_option('datadir') / 'metainfo'
)

install_data(
  'icons/hicolor/scalable/apps/io.github.vovche.Rigs.svg',
  install_dir: get_option('datadir') / 'icons/hicolor/scalable/apps'
)

install_data(
  'icons/hicolor/symbolic/apps/io.github.vovche.Rigs-symbolic.svg',
  install_dir: get_option('datadir') / 'icons/hicolor/symbolic/apps'
)

foreach size : ['48x48', '64x64', '128x128', '256x256', '512x512']
  install_data(
    'icons/hicolor' / size / 'apps/io.github.vovche.Rigs.png',
    install_dir: get_option('datadir') / 'icons/hicolor' / size / 'apps'
  )
endforeach

gnome.post_install(
  gtk_update_icon_cache: true,
)
