# Two layers (see ARCHITECTURE.md):
#   core/ — models, drivers, host commands, diagnostics. GLib/GIO only: it is built
#           WITHOUT gtk4/libadwaita, so any widget code here fails to compile.
#   ui/   — GTK widgets and the application; depends on core.
core_sources = [
  'core/host_command.vala',
  'core/metrics.vala',
  'core/qemu_monitor.vala',
  'core/resource.vala',
  'core/resource_store.vala',
  'core/resource_presets.vala',
  'core/window_state.vala',
  'core/resource_issue.vala',
  'core/failure_rules.vala',
  'core/resource_actions.vala',
  'core/monitor.vala',
  'core/resource_discovery.vala',
  'core/search_provider.vala',
  'core/system_diagnostics.vala',
  'core/guest_agent.vala',
  'core/guest_memory.vala',
  'core/guest_media.vala',
  'core/guest_tools_packages.vala',
  'core/windows_guest_installer.vala',
  'core/drivers/driver.vala',
  'core/drivers/driver_registry.vala',
  'core/drivers/compose_driver.vala',
  'core/drivers/container_driver.vala',
  'core/drivers/libvirt_driver.vala',
  'core/drivers/scripted_qemu_driver.vala',
  config_vala,
]

core_deps = [glib_dep, gio_dep, gio_unix_dep, json_dep, soup_dep, posix_dep, m_dep]

rigs_core = static_library('rigs-core', core_sources, dependencies: core_deps)
rigs_core_dep = declare_dependency(link_with: rigs_core, dependencies: core_deps,
  include_directories: include_directories('.'))

ui_sources = [
  'ui/main.vala',
  'ui/application.vala',
  'ui/window.vala',
  'ui/host_overview.vala',
  'ui/resource_list.vala',
  'ui/resource_card.vala',
  'ui/sparkline.vala',
  'ui/add_resource_dialog.vala',
  'ui/resource_editor_page.vala',
  'ui/guest_tools_dialog.vala',
  'ui/guest_driver_setup_dialog.vala',
  'ui/issue_dialog.vala',
]

executable('rigs',
  ui_sources,
  resources,
  dependencies: [rigs_core_dep, gtk_dep, adw_dep],
  install: true,
)
