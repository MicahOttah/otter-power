#!/bin/bash
APPLET_ID="io.github.micahottah.otterpower"
ok=0
bad=0
chk() {
  if eval "$2" >/dev/null 2>&1; then echo "PASS  $1"; ok=$((ok+1)); else echo "FAIL  $1"; bad=$((bad+1)); fi
}
applet_ok() {
  [ -d "/usr/share/plasma/plasmoids/$APPLET_ID" ] || kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -q "$APPLET_ID"
}
readout() {
  local r="$HOME/.local/bin/powerctl-read.sh"
  [ -r "$r" ] || r=/usr/bin/powerctl-read
  sh "$r"
}

chk "user is in wheel group" 'id -nG | tr " " "\n" | grep -qx wheel'
chk "platform profile writable" '[ -w /sys/firmware/acpi/platform_profile ]'
chk "EPP writable" '[ -w /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference ]'
chk "power limit writable" '[ -w /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw ]'
chk "burst window writable" '[ -w /sys/class/powercap/intel-rapl-mmio:0/constraint_0_time_window_us ]'
chk "package energy readable" '[ -r /sys/class/powercap/intel-rapl:0/energy_uj ]'
chk "rapl-limit.service enabled" 'systemctl is-enabled rapl-limit.service'
chk "powerctl-resume.service enabled" 'systemctl is-enabled powerctl-resume.service'
chk "powerctl-restore.service enabled (user)" 'systemctl --user is-enabled powerctl-restore.service'
chk "applet installed" applet_ok
chk "read script prints 15 lines" '[ "$(readout | wc -l)" -eq 15 ]'

if [ -r "$HOME/.config/powerctl/pl1" ]; then
  want=$(( $(cat "$HOME/.config/powerctl/pl1") * 1000000 ))
  have=$(cat /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw 2>/dev/null)
  chk "live power limit matches saved choice" '[ "$want" = "$have" ]'
fi
if [ -r "$HOME/.config/powerctl/pl1_window" ]; then
  want=$(cat "$HOME/.config/powerctl/pl1_window")
  have=$(( ($(cat /sys/class/powercap/intel-rapl-mmio:0/constraint_0_time_window_us 2>/dev/null || echo 0) + 500000) / 1000000 ))
  chk "live burst window matches saved choice" '[ "$want" = "$have" ]'
fi

echo
echo "$ok passed, $bad failed"
[ "$bad" -eq 0 ]
