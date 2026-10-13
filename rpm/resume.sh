#!/bin/sh
# Reapply limits after resume, then each logged-in user's saved choices.
systemd-tmpfiles --create /usr/lib/tmpfiles.d/otter-power-cpu-epp.conf
/bin/sh /usr/libexec/otter-power/set-rapl-limit.sh
sleep 2
for uid in $(loginctl list-users --no-legend | awk '{print $1}'); do
  user=$(id -un "$uid" 2>/dev/null) || continue
  runuser -u "$user" -- /usr/bin/powerctl-restore
done
exit 0
