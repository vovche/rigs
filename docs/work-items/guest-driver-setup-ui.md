# Work Packet: Guest driver setup dialog

## Owned target
- src/guest_driver_setup_dialog.vala

## Contract
Adw.Dialog subclass Rigs.GuestDriverSetupDialog(VmModel vm). Parent opens from
GuestToolsDialog after saving OS + QGA socket config. UI all translatable `_()`.
Use existing Libadwaita patterns, accessible labels, wrapped subtitles, no markup
for resource names/errors. No WinRM or credential UI.

Dependencies already implemented:
WindowsGuestInstaller: probe(vm) -> GuestToolsProbe available,compatible,
administrator,balloon_service_running,architecture,version,summary.
install(vm,GuestToolsArtifact,uint timeout_ms=600000)->GuestInstallResult fields
state enum SUCCEEDED,REBOOT_REQUIRED,FAILED,TIMED_OUT;summary,journal_path,
remote_directory;exit_code. signal progress(string). has_pending(vm),resume(vm,uint=5000),reboot(vm).
GuestToolsPackages: const VERSION; fetch(bool iso,Cancellable? cancel=null)
->GuestToolsArtifact fields path,sha256,version,iso; signal progress(int64 received,int64 total).
static local_file(path,bool iso)->artifact (hash/format checked; local EXE still
must pass Authenticode inside Windows). Pinned official download verifies SHA.
GuestMedia.list_drives(vm)->GenericArray<GuestOpticalDrive> id,current_iso;
attach(vm,iso_path,drive_id) validates empty target and stages for container.

## UX
On open run read-only probe + list_drives on worker thread, then show agent/OS/admin
and CD-drive availability. Failure is explicit with bootstrap guidance, not a
false missing-driver assertion. No automatic installation or media mutation.
Keep Copy/Save config outside this dialog (parent). No technical shell input.
- Prepare Installer downloads EXE on worker, shows package version/SHA and enables
  Install Drivers only after probe compatible+admin and no pending job. Offer
  Choose Local Installer (Gtk.FileDialog) fallback; file path resolved.
- Install Drivers confirmation names VM/package, explains admin driver changes,
  no forced restart; on response run installer.install off GTK thread.
- Check Installation Result button when has_pending, calls resume without
  new install; unknown outcome keeps new installation blocked.
- Show summary, journal path (open with Gtk.FileLauncher), remote_directory log
  location selectable, and Restart Windows only for REBOOT_REQUIRED. Restart
  requires own user confirmation about unsaved work, calls installer.reboot
  off GTK thread; never automatic.
- Download and Attach VirtIO ISO / Choose Local ISO: only selected empty CD drive,
  show dropdown if drives available, occupied drives cannot be selected for action;
  off-thread download/validate/attach. Does not replace existing media.
- After ISO attachment guide user to Windows console -> CD drive ->
  virtio-win-guest-tools.exe as administrator (retain Balloon and Guest Agent).
  Explain VM also needs virtio-serial QGA channel; no agent means one manual
  installation step, never autostart/WinRM hacks.

All blocking calls off GTK thread; marshal progress/results via Idle.add.
Prevent duplicate jobs/buttons; while installing disable close via can_close,
never kill remote installer. Download has Cancel button using Cancellable;
installer phase cannot be canceled by killing processes. On dismissed dialog
ignore callbacks safely. Persisted journals allow later resume after app exit.
Capture model snapshot before worker reads to avoid settings race.
No tests/new build files here; parent handles build/tests/docs/translations.
