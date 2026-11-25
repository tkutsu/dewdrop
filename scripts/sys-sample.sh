#!/bin/sh
# What the system monitor (src/services/Sys.qml) samples, one section per
# argument: temps, light, procs or disks. Sys parses what each prints.
#
# Every sysfs value is taken with `read`, which is a shell builtin, rather
# than with `$(cat ...)`, which is a fork each. The chip names alone were one
# per hwmon directory whether or not the chip turned out to be the CPU's, and
# the light section measured six times what it costs now: 8.6ms against
# 1.3ms on this machine. The greps are left as they are: three processes for
# three files, where the shell equivalent would be slower and unreadable.

# The CPU's temperatures: label, millidegrees and path per sensor. The path
# is what the badge's own reader is resolved from.
#
# hwmon numbers are handed out in probe order and shuffle between boots, so
# the CPU's chip is found by name every time instead of being remembered as a
# path. Only the CPU's own chips are asked: the board, the NVMe and the wifi
# card all publish temperatures too, and none of them are this module.
temps() {
	for d in /sys/class/hwmon/*; do
		read -r n < "$d/name"
		case $n in
		k10temp | zenpower* | coretemp | cpu_thermal) ;;
		*) continue ;;
		esac
		for f in "$d"/temp*_input; do
			l="${f%_input}_label"
			[ -r "$l" ] || continue
			read -r lab < "$l"
			read -r val < "$f"
			printf '%s\t%s\t%s\n' "$lab" "$val" "$f"
		done
	done
}

# Every chip this time, not just the CPU's: the fans hang off whatever the
# board's Super-I/O is, which is a different chip from the one that reports
# the temperatures. Chip and file name first, so a fan with no label of its
# own still has something to be called; the label goes last because it is the
# field that can hold spaces.
fans() {
	for f in /sys/class/hwmon/*/fan*_input; do
		[ -r "$f" ] || continue
		l="${f%_input}_label"
		d="${f%/*}"
		b="${f##*/}"
		read -r n < "$d/name"
		read -r rpm < "$f"
		lab=""
		[ -r "$l" ] && read -r lab < "$l"
		printf '%s\t%s\t%s\t%s\n' "$n" "${b%_input}" "$rpm" "$lab"
	done
}

# The popup's cheap poll: CPU, clocks, temperatures, memory and fans, each
# under a ":name" line.
light() {
	echo :cpu
	grep ^cpu /proc/stat
	echo :freq
	# Measured, not requested: on AMD this line comes from aperf/mperf, where
	# cpufreq's scaling_cur_freq is the governor's last ask.
	grep '^cpu MHz' /proc/cpuinfo
	echo :temp
	temps
	echo :mem
	grep -E '^(MemTotal|MemAvailable|Cached|SReclaimable|Shmem|SwapTotal|SwapFree):' /proc/meminfo
	echo :fan
	fans
}

# Every process's pid, parent, accumulated CPU time, resident size and name in
# one pass, which is the only way to get a *current* per-process load: ps and
# /proc's own percentages are averages over a process's whole life, so a
# browser that was busy an hour ago outranks the compile running now.
#
# /proc/<pid>/stat cannot simply be split on spaces: the command name sits in
# brackets and may contain both spaces and brackets. So the name is cut out
# between the first "(" and the last ")", and the numbered fields are counted
# from what is left. ppid is field 4, utime + stime is 14 + 15, and rss is 24.
#
# cat reads the files rather than awk: a process can exit between the glob and
# the open, and gawk takes a file it cannot open as fatal and stops there,
# dropping every pid above it from the sample. That was about one sample in a
# hundred, and it emptied the lists. cat skips the file.
procs() {
	cat /proc/[0-9]*/stat 2>/dev/null | awk '{
		n = $0; sub(/.*\) /, "", n); split(n, f, " ")
		c = $0; sub(/^[0-9]+ \(/, "", c); sub(/\)[^)]*$/, "", c)
		print $1, f[2], f[12] + f[13], f[22], c
	}'
}

# The disks' warmth and work, out of sysfs with no forks at all.
#
# A block device's `device` link is the controller, and the controller is
# where the driver hangs its hwmon, so /sys/block/<d>/device/hwmon*/temp1_input
# is the drive's own temperature without matching a hwmon number against a
# disk (hwmon numbers are handed out in probe order). temp1 is the composite
# reading on NVMe and the only one on SATA.
#
# /sys/block/<d>/stat is /proc/diskstats' line for that disk without the name
# on the front: sectors read is field 3, sectors written field 7, and field 10
# is milliseconds spent with anything in flight, which over a known interval
# is the drive's own utilisation.
#
# Then a "dm" line per device-mapper device (LUKS, LVM): its dm-N name, the
# name it has under /dev/mapper, and what it sits on (`slaves`), so a
# filesystem df finds on /dev/mapper/cryptroot can be put on its disk.
disks() {
	for d in /sys/block/*; do
		b=${d##*/}
		case $b in
		loop* | ram* | zram* | dm-* | md* | sr*) continue ;;
		esac
		[ -r "$d/device/model" ] || continue
		read -r m < "$d/device/model"
		read -r st < "$d/stat"
		t=
		for h in "$d"/device/hwmon*/temp1_input; do
			[ -r "$h" ] && read -r t < "$h" && break
		done
		printf '%s\t%s\t%s\t%s\n' "$b" "$t" "$st" "$m"
	done
	for d in /sys/block/dm-*; do
		[ -r "$d/dm/name" ] || continue
		read -r n < "$d/dm/name"
		s=
		for x in "$d"/slaves/*; do
			[ -e "$x" ] && s="$s ${x##*/}"
		done
		printf 'dm\t%s\t%s\t%s\n' "${d##*/}" "$n" "$s"
	done
}

case ${1-} in
temps | light | procs | disks) "$1" ;;
*)
	echo "usage: sys-sample.sh temps|light|procs|disks" >&2
	exit 2
	;;
esac
