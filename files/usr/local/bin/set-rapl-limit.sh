#!/bin/sh
f=/sys/class/powercap/intel-rapl-mmio:0/constraint_0_power_limit_uw
w=/sys/class/powercap/intel-rapl-mmio:0/constraint_0_time_window_us
i=0
while [ ! -w "$f" ] && [ "$i" -lt 30 ]; do
  sleep 1
  i=$((i+1))
done
chgrp wheel "$f" "$w" 2>/dev/null
chmod 664 "$f" "$w" 2>/dev/null
echo 75000000 > "$f"
echo 28000000 > "$w"
