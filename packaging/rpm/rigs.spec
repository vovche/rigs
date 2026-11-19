# Fedora / RHEL-family package. Local snapshot builds: scripts/package.sh rpm
# (passes --define "snapshot .gitN.SHA"); releases build from the v%{version} tag.
Name:           rigs
Version:        0.9.0
Release:        1%{?snapshot}%{?dist}
Summary:        Native GNOME hub for virtual machines and containers
License:        Apache-2.0
URL:            https://github.com/vovche/rigs
Source0:        %{url}/archive/refs/tags/v%{version}/%{name}-%{version}.tar.gz

BuildRequires:  gcc
BuildRequires:  meson >= 0.59
BuildRequires:  vala
BuildRequires:  gettext
BuildRequires:  desktop-file-utils
BuildRequires:  pkgconfig(glib-2.0) >= 2.76
BuildRequires:  pkgconfig(gtk4) >= 4.10
BuildRequires:  pkgconfig(libadwaita-1) >= 1.5
BuildRequires:  pkgconfig(json-glib-1.0)
BuildRequires:  pkgconfig(libsoup-3.0)

Recommends:     (podman or docker)
Suggests:       qemu-kvm
Suggests:       libvirt-client
Suggests:       virt-viewer
Suggests:       remmina

%description
Rigs starts, stops and monitors local QEMU/KVM virtual machines, Podman and
Docker containers, Compose projects and libvirt domains. It shows live CPU and
memory graphs, hot-swaps ISO images, explains failed starts in plain language
and integrates with GNOME Shell search.

%prep
%autosetup -n %{name}-%{version}

%build
%meson
%meson_build

%install
%meson_install
%find_lang %{name}

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/io.github.vovche.Rigs.desktop
%meson_test

%files -f %{name}.lang
%{_bindir}/rigs
%{_datadir}/applications/io.github.vovche.Rigs.desktop
%{_datadir}/metainfo/io.github.vovche.Rigs.metainfo.xml
%{_datadir}/gnome-shell/search-providers/io.github.vovche.Rigs.search-provider.ini
%{_datadir}/dbus-1/services/io.github.vovche.Rigs.service
%{_datadir}/icons/hicolor/*/apps/io.github.vovche.Rigs.png
%{_datadir}/icons/hicolor/scalable/apps/io.github.vovche.Rigs.svg
%{_datadir}/icons/hicolor/symbolic/apps/io.github.vovche.Rigs-symbolic.svg

%changelog
* Thu Nov 19 2026 vovche <vovche@users.noreply.github.com> - 0.9.0-1
- Packaging for Fedora.
