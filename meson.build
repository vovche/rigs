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
soup_dep = dependency('libsoup-3.0')
posix_dep = meson.get_compiler('vala').find_library('posix')
m_dep = meson.get_compiler('c').find_library('m', required: false)

i18n = import('i18n')

conf_data = configuration_data()
conf_data.set_quoted('GETTEXT_PACKAGE', 'rigs')
conf_data.set_quoted('VERSION', meson.project_version())
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
  'tests/test_resource_presets.vala',
  'tests/test_guest_memory.vala',
  'tests/test_guest_agent.vala',
  'tests/test_guest_media.vala',
  'tests/test_guest_tools_packages.vala',
  'tests/test_windows_guest_installer.vala',
  'tests/test_host_command.vala',
  'tests/test_discovery.vala',
  'tests/test_runtime_drivers.vala',
  'tests/test_drivers.vala',
  'tests/test_diagnostics.vala',
  'tests/test_failure_rules.vala',
  'tests/test_regressions.vala',
  'tests/test_search_provider.vala',
  'tests/mock_driver.vala',
]

test_exe = executable('rigs-tests',
  test_sources,
  # Core only: tests cannot depend on GTK, so they stay headless by construction.
  dependencies: [rigs_core_dep],
)

test('unit-tests', test_exe)

# Guardrails: see docs/guardrails.md. Both run as part of ./build.sh (meson test).
bash = find_program('bash')
test('lint', bash, args: [files('scripts/lint.sh'), meson.project_source_root()])
test('lint-selftest', bash, args: [files('scripts/lint_selftest.sh'), meson.project_source_root()])
