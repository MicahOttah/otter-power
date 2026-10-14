#!/bin/sh
profile=$(cat /sys/firmware/acpi/platform_profile 2>/dev/null)

cpu=""
for d in /sys/class/hwmon/hwmon*; do
  n=$(cat "$d/name" 2>/dev/null)
  case "$n" in
    coretemp|k10temp|zenpower)
      cpu=$(cat "$d/temp1_input" 2>/dev/null)
      [ -n "$cpu" ] && break ;;
  esac
done

fans=""
for d in /sys/class/hwmon/hwmon*; do
  [ "$(cat "$d/name" 2>/dev/null)" = "dell_smm" ] || continue
  for x in "$d"/fan*_input; do
    [ -r "$x" ] && fans="$fans $(cat "$x")"
  done
  break
done

gpu=""
gpurest=""
if [ "$1" = "gpu" ] && command -v nvidia-smi >/dev/null 2>&1; then
  asleep=""
  for p in /sys/bus/pci/devices/*; do
    [ "$(cat "$p/vendor" 2>/dev/null)" = "0x10de" ] || continue
    case "$(cat "$p/class" 2>/dev/null)" in 0x03*) ;; *) continue ;; esac
    [ "$(cat "$p/power/runtime_status" 2>/dev/null)" = "suspended" ] && asleep=1
  done
  if [ -n "$asleep" ]; then
    gpu="asleep"
    gpurest="asleep"
  else
    q=$(nvidia-smi --query-gpu=temperature.gpu,power.draw,utilization.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -1)
    gpu=${q%%,*}
    gpurest=${q#*,}
  fi
fi

epp=$(cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference 2>/dev/null)

dimm=""
for d in /sys/class/hwmon/hwmon*; do
  [ "$(cat "$d/name" 2>/dev/null)" = "spd5118" ] || continue
  v=$(cat "$d/temp1_input" 2>/dev/null)
  [ -n "$v" ] && { [ -z "$dimm" ] || [ "$v" -gt "$dimm" ]; } && dimm=$v
done

thr=$(cat /sys/devices/system/cpu/cpu0/thermal_throttle/package_throttle_count 2>/dev/null)

rapl=""
for d in /sys/class/powercap/intel-rapl:*; do
  [ "$(cat "$d/name" 2>/dev/null)" = "package-0" ] || continue
  rapl=$(cat "$d/energy_uj" 2>/dev/null)
  break
done

bat=""
b=/sys/class/power_supply/BAT0
if [ -r "$b/status" ]; then
  bat="$(cat "$b/status" 2>/dev/null)|$(cat "$b/current_now" 2>/dev/null)|$(cat "$b/voltage_now" 2>/dev/null)"
fi

freq=$(cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null | sort -n | tail -1)

nvme=""
for d in /sys/class/hwmon/hwmon*; do
  [ "$(cat "$d/name" 2>/dev/null)" = "nvme" ] || continue
  v=$(cat "$d/temp1_input" 2>/dev/null)
  [ -n "$v" ] && { [ -z "$nvme" ] || [ "$v" -gt "$nvme" ]; } && nvme=$v
done

pl1=$(cat /sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw 2>/dev/null)
tw=$(cat /sys/class/powercap/intel-rapl-mmio:0/constraint_0_time_window_us 2>/dev/null)
ptxt=$(cat "$HOME/.config/powerctl/panel_text" 2>/dev/null)

printf '%s\n' "$profile" "$cpu" "$fans" "$gpu" "$epp" "$dimm" "$thr" "$rapl" "$bat" "$freq" "$nvme" "$gpurest" "$pl1" "$tw" "$ptxt"
