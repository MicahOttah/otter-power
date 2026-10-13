#!/bin/sh
d="$HOME/.config/powerctl"
[ -r "$d/profile" ] && cat "$d/profile" > /sys/firmware/acpi/platform_profile 2>/dev/null
if [ -r "$d/epp" ]; then
  v=$(cat "$d/epp")
  for f in /sys/devices/system/cpu/cpu*/cpufreq/energy_performance_preference; do
    [ -w "$f" ] && echo "$v" > "$f" 2>/dev/null
  done
fi
if [ -r "$d/pl1" ]; then
  w=$(cat "$d/pl1")
  case "$w" in
    ''|*[!0-9]*) ;;
    *)
      f=/sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw
      [ -w "$f" ] && echo $((w * 1000000)) > "$f" 2>/dev/null
      ;;
  esac
fi
if [ -r "$d/pl1_window" ]; then
  s=$(cat "$d/pl1_window")
  case "$s" in
    ''|*[!0-9]*) ;;
    *)
      f=/sys/class/powercap/intel-rapl-mmio:0/constraint_0_time_window_us
      [ -w "$f" ] && echo $((s * 1000000)) > "$f" 2>/dev/null
      ;;
  esac
fi
exit 0
