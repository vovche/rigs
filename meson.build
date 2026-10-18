project('rigs', ['c', 'vala'],
  version: '0.9.0',
  meson_version: '>= 0.59.0',
  default_options: [
    'warning_level=2',
    'werror=false',
  ],
)

add_project_arguments([
  '--target-glib=2.76',
], language: 'vala')

add_project_arguments([
  '-DGETTEXT_PACKAGE="rigs"',
], language: 'c')

gtk_dep = dependency('gtk4', version: '>= 4.10')
adw_dep = dependency('libadwaita-1', version: '>= 1.5')
json_dep = dependency('json-glib-1.0')
glib_dep = dependency('glib-2.0', version: '>= 2.76')
gio_dep = dependency('gio-2.0')
gio_unix_dep = dependency('gio-unix-2.0')
posix_dep = meson.get_compiler('vala').find_library('posix')
m_dep = meson.get_compiler('c').find_library('m', required: false)

i18n = import('i18n')

conf_data = configuration_data()
conf_data.set_quoted('GETTEXT_PACKAGE', 'rigs')
conf_data.set_quoted('LOCALEDIR', get_option('prefix') / get_option('localedir'))

config_vala = configure_file(
  input: 'src/config.vala.in',
  output: 'config.vala',
  configuration: conf_data,
)

subdir('po')
subdir('data')
subdir('src')

test_sources = [
  'tests/main.vala',
  'tests/test_models.vala',
  'tests/test_guest_memory.vala',
  'tests/test_host_command.vala',
  'tests/test_discovery.vala',
  'tests/test_managed_driver.vala',
  'tests/test_drivers.vala',
  'tests/test_diagnostics.vala',
  'tests/test_search_provider.vala',
  'tests/mock_driver.vala',
  'src/vm_model.vala',
  'src/guest_memory.vala',
  'src/host_command.vala',
  'src/resource_discovery.vala',
  'src/drivers/managed_driver.vala',
  'src/search_provider.vala',
  'src/system_diagnostics.vala',
  'src/drivers/driver.vala',
  'src/drivers/qemu_driver.vala',
  'src/drivers/compose_driver.vala',
  'src/drivers/driver_registry.vala',
]

test_exe = executable('rigs-tests',
  test_sources,
  dependencies: [
    gtk_dep,
    adw_dep,
    glib_dep,
    gio_dep,
    gio_unix_dep,
    json_dep,
    posix_dep,
  ],
)

test('unit-tests', test_exe)
