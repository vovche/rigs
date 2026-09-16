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
