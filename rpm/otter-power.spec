%global applet_id io.github.micahottah.otterpower

Name:           otter-power
Version:        0.2
Release:        1%{?dist}
Summary:        Power and thermal control applet for the Dell Precision 7670 (KDE Plasma 6)
License:        GPL-2.0-or-later
URL:            https://github.com/MicahOttah/otter-power
Source0:        %{name}-%{version}.tar.gz
BuildArch:      noarch
BuildRequires:  systemd-rpm-macros
Requires:       plasma-workspace
Requires:       systemd

%description
Otter Power is a KDE Plasma 6 panel widget for the Dell Precision 7670. It
switches the Dell platform profile, CPU energy preference, CPU sustained power
limit and burst window, offers one-click presets, and shows live power,
temperature and fan readouts. It also installs udev rules, tmpfiles entries and
systemd services that make the needed sysfs files writable by the wheel group
and restore saved settings at boot, login and resume.

Tested on one Dell Precision 7670 only. It changes power and thermal behavior
that the firmware normally owns, so read the README before use.

%prep
%autosetup

%build

%install
install -D -m 755 files/home/bin/powerctl-read.sh %{buildroot}%{_bindir}/powerctl-read
install -D -m 755 files/home/bin/powerctl-restore.sh %{buildroot}%{_bindir}/powerctl-restore
install -D -m 755 files/usr/local/bin/set-rapl-limit.sh %{buildroot}%{_libexecdir}/%{name}/set-rapl-limit.sh
install -D -m 755 rpm/resume.sh %{buildroot}%{_libexecdir}/%{name}/resume.sh
install -D -m 644 files/home/plasmoid/metadata.json %{buildroot}%{_datadir}/plasma/plasmoids/%{applet_id}/metadata.json
install -D -m 644 files/home/plasmoid/contents/ui/main.qml %{buildroot}%{_datadir}/plasma/plasmoids/%{applet_id}/contents/ui/main.qml
sed -i 's|\$HOME/.local/bin/powerctl-read.sh|%{_bindir}/powerctl-read|' %{buildroot}%{_datadir}/plasma/plasmoids/%{applet_id}/contents/ui/main.qml
grep -q '%{_bindir}/powerctl-read' %{buildroot}%{_datadir}/plasma/plasmoids/%{applet_id}/contents/ui/main.qml
install -D -m 644 files/etc/tmpfiles.d/cpu-epp.conf %{buildroot}%{_tmpfilesdir}/otter-power-cpu-epp.conf
install -D -m 644 files/etc/tmpfiles.d/platform-profile.conf %{buildroot}%{_tmpfilesdir}/otter-power-platform-profile.conf
install -D -m 644 files/etc/udev/rules.d/91-platform-profile.rules %{buildroot}%{_udevrulesdir}/91-platform-profile.rules
install -D -m 644 files/etc/udev/rules.d/92-rapl-perms.rules %{buildroot}%{_udevrulesdir}/92-rapl-perms.rules
install -D -m 644 rpm/rapl-limit.service %{buildroot}%{_unitdir}/rapl-limit.service
install -D -m 644 rpm/powerctl-resume.service %{buildroot}%{_unitdir}/powerctl-resume.service
install -D -m 644 rpm/powerctl-restore.service %{buildroot}%{_userunitdir}/powerctl-restore.service

%post
systemctl enable rapl-limit.service powerctl-resume.service >/dev/null 2>&1 || :
systemctl --global enable powerctl-restore.service >/dev/null 2>&1 || :
systemd-tmpfiles --create %{_tmpfilesdir}/otter-power-cpu-epp.conf %{_tmpfilesdir}/otter-power-platform-profile.conf >/dev/null 2>&1 || :
udevadm control --reload >/dev/null 2>&1 || :
udevadm trigger --subsystem-match=powercap --action=change >/dev/null 2>&1 || :
udevadm trigger --subsystem-match=platform-profile --action=change >/dev/null 2>&1 || :

%preun
%systemd_preun rapl-limit.service powerctl-resume.service
%systemd_user_preun powerctl-restore.service

%postun
%systemd_postun rapl-limit.service powerctl-resume.service
%systemd_user_postun powerctl-restore.service
udevadm control --reload >/dev/null 2>&1 || :

%files
%license LICENSE
%doc README.md
%{_bindir}/powerctl-read
%{_bindir}/powerctl-restore
%{_libexecdir}/%{name}/
%{_datadir}/plasma/plasmoids/%{applet_id}/
%{_tmpfilesdir}/otter-power-cpu-epp.conf
%{_tmpfilesdir}/otter-power-platform-profile.conf
%{_udevrulesdir}/91-platform-profile.rules
%{_udevrulesdir}/92-rapl-perms.rules
%{_unitdir}/rapl-limit.service
%{_unitdir}/powerctl-resume.service
%{_userunitdir}/powerctl-restore.service

%changelog
* Tue Oct 13 2026 MicahOttah - 0.2-1
- Initial RPM package
