#!/bin/bash
set -e
if [ "$(id -u)" -eq 0 ]; then echo "Run this as your normal user, not root."; exit 1; fi
APPLET_ID="io.github.micahottah.otterpower"
D=$(cd "$(dirname "$0")" && pwd)
U=$(id -un)
H=$HOME

echo "== packages"
sudo dnf install -y plasma-sdk kf6-kpackage lm_sensors

echo "== wheel group"
if ! id -nG | tr ' ' '\n' | grep -qx wheel; then
  sudo usermod -aG wheel "$U"
  echo "Added $U to wheel. Log out and back in before the toggles will work."
fi

echo "== user files"
mkdir -p "$H/.local/bin" "$H/.config/systemd/user" "$H/plasmoids/$APPLET_ID/contents/ui"
install -m 755 "$D/files/home/bin/powerctl-read.sh" "$H/.local/bin/powerctl-read.sh"
install -m 755 "$D/files/home/bin/powerctl-restore.sh" "$H/.local/bin/powerctl-restore.sh"
install -m 644 "$D/files/home/systemd-user/powerctl-restore.service" "$H/.config/systemd/user/powerctl-restore.service"
install -m 644 "$D/files/home/plasmoid/metadata.json" "$H/plasmoids/$APPLET_ID/metadata.json"
install -m 644 "$D/files/home/plasmoid/contents/ui/main.qml" "$H/plasmoids/$APPLET_ID/contents/ui/main.qml"
systemctl --user daemon-reload || true
systemctl --user enable powerctl-restore.service || echo "Could not enable the user service here. Run: systemctl --user enable powerctl-restore.service"

echo "== applet"
if kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -q "$APPLET_ID"; then
  kpackagetool6 -t Plasma/Applet -u "$H/plasmoids/$APPLET_ID"
else
  kpackagetool6 -t Plasma/Applet -i "$H/plasmoids/$APPLET_ID"
fi

echo "== system files"
sudo install -m 644 "$D/files/etc/tmpfiles.d/cpu-epp.conf" /etc/tmpfiles.d/cpu-epp.conf
sudo install -m 644 "$D/files/etc/tmpfiles.d/platform-profile.conf" /etc/tmpfiles.d/platform-profile.conf
sudo install -m 644 "$D/files/etc/udev/rules.d/91-platform-profile.rules" /etc/udev/rules.d/91-platform-profile.rules
sudo install -m 644 "$D/files/etc/udev/rules.d/92-rapl-perms.rules" /etc/udev/rules.d/92-rapl-perms.rules
sudo install -m 755 "$D/files/usr/local/bin/set-rapl-limit.sh" /usr/local/bin/set-rapl-limit.sh
sudo install -m 644 "$D/files/etc/systemd/system/rapl-limit.service" /etc/systemd/system/rapl-limit.service
sudo tee /etc/systemd/system/powerctl-resume.service > /dev/null << EOF
[Unit]
Description=Reapply EPP permissions, power limit and saved power settings after resume
After=suspend.target hibernate.target hybrid-sleep.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'systemd-tmpfiles --create /etc/tmpfiles.d/cpu-epp.conf; /bin/sh /usr/local/bin/set-rapl-limit.sh; sleep 2; su - $U -c "$H/.local/bin/powerctl-restore.sh"'

[Install]
WantedBy=suspend.target hibernate.target hybrid-sleep.target
EOF
sudo restorecon -v /etc/systemd/system/rapl-limit.service /etc/systemd/system/powerctl-resume.service /usr/local/bin/set-rapl-limit.sh >/dev/null 2>&1 || true

echo "== activate"
sudo systemd-tmpfiles --create /etc/tmpfiles.d/cpu-epp.conf /etc/tmpfiles.d/platform-profile.conf || true
sudo udevadm control --reload
sudo udevadm trigger --subsystem-match=powercap --action=change
sudo udevadm trigger --subsystem-match=platform-profile --action=change
sudo systemctl daemon-reload
sudo systemctl enable rapl-limit.service powerctl-resume.service

echo
echo "Done. Restart the panel with: plasmashell --replace >/dev/null 2>&1 & disown"
echo "Then add the 'Otter Power' widget to a panel, and run verify.sh."
