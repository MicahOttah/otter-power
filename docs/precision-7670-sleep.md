# Dell Precision 7670: sleep on Linux

Notes from getting suspend working properly on a Dell Precision 7670 (BIOS 1.40) with Fedora 44. Tested on one machine only, so your results may differ.

## Summary

- The BIOS defines S3 sleep in its ACPI tables but keeps it disabled, so Linux only gets suspend-to-idle (s2idle, also called Modern Standby or S0ix).
- On this unit, suspend-to-idle woke up within seconds every time. The cause was the I2C touchpad, which is enabled as a wake source.
- With touchpad wake disabled, the machine stays asleep, reaches full S0ix residency and stays cool. It wakes with the power button, the lid or a USB mouse. The built-in keyboard does not wake it.

## Why there is no S3

The kernel only offers suspend-to-idle:

```bash
cat /sys/power/mem_sleep
sudo dmesg | grep -i "supports S"
```

On BIOS 1.40 these print `s2idle` and `ACPI: PM: (supports S0 S4 S5)`.

The ACPI tables show why. Dump and decompile them:

```bash
sudo dnf install -y acpica-tools
mkdir -p /tmp/acpi && cd /tmp/acpi
sudo acpidump -b
sudo chown "$USER" *.dat
iasl -d dsdt.dat facp.dat
grep -n -B2 -A8 "If (SS3)" dsdt.dsl
grep -i "Low Power S0" facp.dsl
```

The DSDT defines `_S3` only inside `If (SS3)`, and that flag is never set. S4 sits behind a similar `SS4` flag, which is set, so the firmware deliberately hides S3. The FADT advertises Low Power S0 Idle.

Forcing S3 by loading a patched DSDT is possible, but not recommended. If the firmware doesn't prepare for an S3 resume, a failed resume is a hard crash.

## Finding what wakes the machine

Turn on extra suspend logging (it lasts until reboot) and suspend:

```bash
echo 1 | sudo tee /sys/power/pm_debug_messages
systemctl suspend
```

After it wakes, check what the kernel recorded:

```bash
cat /sys/power/pm_wakeup_irq
sudo dmesg | tail -80 | grep -i -E "Triggering wakeup|Wakeup|EC:|suspend-to-idle|PM: suspend"
```

Then find which device owns that interrupt. On this unit, IRQ 9 is ACPI and IRQ 14 is the Intel GPIO controller (`INTC1056:00`):

```bash
grep -E "^ *14:" /proc/interrupts
grep -i "intel-gpio" /proc/interrupts
sudo grep -i -E "irq|wake" /sys/kernel/debug/gpio
```

Here the GPIO interrupt was pin 355, labeled `TPD0` (the touchpad), on device `VEN_0488:00`.

List every device that is allowed to wake the machine:

```bash
for f in /sys/bus/*/devices/*/power/wakeup; do [ "$(cat $f 2>/dev/null)" = enabled ] && echo "$f"; done
```

## The fix: disable touchpad wake

Check your touchpad's device name first, since it may differ:

```bash
ls /sys/bus/i2c/devices/ | grep -i VEN
```

Test it until the next reboot:

```bash
echo disabled | sudo tee /sys/bus/i2c/devices/i2c-VEN_0488:00/power/wakeup
```

Make it permanent with a udev rule:

```bash
sudo tee /etc/udev/rules.d/93-touchpad-nowake.rules > /dev/null << 'RULE'
# Stop the I2C touchpad (TPD0, VEN_0488) from waking the machine from suspend.
ACTION=="add", SUBSYSTEM=="i2c", KERNEL=="i2c-VEN_0488:00", ATTR{power/wakeup}="disabled"
RULE
sudo udevadm control --reload
```

After a reboot, this should print `disabled`:

```bash
cat /sys/bus/i2c/devices/i2c-VEN_0488:00/power/wakeup
```

## Checking that sleep really saves power

Suspend-to-idle only saves power if the chipset reaches its deepest idle state. Read these counters, sleep for a few minutes, then read them again:

```bash
cat /sys/power/low_power_idle_system_residency_us
sudo cat /sys/kernel/debug/pmc_core/slp_s0_residency_usec
```

Both should rise by roughly the time the machine slept, in microseconds. If they barely move, something is still keeping the machine partly awake.

USB devices can still wake the machine, so unplug a mouse or wireless dongle before putting the laptop in a bag.

## Things that did not help

- `acpi.ec_no_wakeup=1` stops the immediate wakes, but it also stops the power button and keyboard from waking the machine. Not recommended.
- `mem_sleep_default=deep` does nothing on this BIOS, because S3 is not offered. It can be removed with `sudo grubby --update-kernel=ALL --remove-args="mem_sleep_default=deep"`.
- Hibernate is not a fallback with Secure Boot enabled, because kernel lockdown blocks it.

## Harmless noise

- The embedded controller raises an ACPI event about five times per second, even at idle. During suspend the kernel handles these and goes back to sleep, so they do not cause wakes.
- The SMBus controller has SPD Write Disable set, so the DDR5 temperature sensor (`spd5118`) logs errors on every resume, and `sensors` may print a `temp1_max_alarm` error. The DIMM temperature reading still works.
