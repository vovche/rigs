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
