project('rigs', ['c', 'vala'],
  version: '1.0.0',
  meson_version: '>= 0.59.0',
  default_options: [
    'warning_level=2',
    'werror=false',
  ],
)

add_project_arguments([
  '--target-glib=2.76',
], language: 'vala')

gtk_dep = dependency('gtk4', version: '>= 4.10')
adw_dep = dependency('libadwaita-1', version: '>= 1.4')
json_dep = dependency('json-glib-1.0')
glib_dep = dependency('glib-2.0', version: '>= 2.76')
gio_dep = dependency('gio-2.0')
posix_dep = meson.get_compiler('vala').find_library('posix')

subdir('data')
subdir('src')

test_sources = [
  'tests/main.vala',
  'tests/test_models.vala',
  'tests/test_drivers.vala',
  'src/vm_model.vala',
  'src/drivers/driver.vala',
  'src/drivers/qemu_driver.vala',
  'src/drivers/compose_driver.vala',
  'src/drivers/driver_registry.vala',
]

test_exe = executable('rigs-tests',
  test_sources,
  dependencies: [
    glib_dep,
    gio_dep,
    json_dep,
    posix_dep,
  ],
)

test('unit-tests', test_exe)
