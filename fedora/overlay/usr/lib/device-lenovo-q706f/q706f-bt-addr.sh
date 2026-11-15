#!/bin/sh
# QCA6390 NVM uses the chip default 00:00:00:00:5A:AD, so the kernel leaves
# hci0 unconfigured until userspace sets a public address.
# Order: /etc/q706f-bt-addr (first non-comment line, see
# q706f-bt-addr.example), the factory address on the persist partition
# (bluetooth/.bid or bt_nv.bin), the permanent Wi-Fi MAC + 1, and finally a
# stable address derived from machine-id. A missing, empty or invalid
# /etc/q706f-bt-addr is skipped.
addr_file=/etc/q706f-bt-addr
mnt=/run/q706f-persist

usable() {
	mac=$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')
	printf '%s' "$mac" | grep -Eq '^[0-9A-F]{2}(:[0-9A-F]{2}){5}$' || return 1
	case "$mac" in
	00:00:00:00:00:00|FF:FF:FF:FF:FF:FF|00:00:00:00:5A:AD) return 1 ;;
	esac
	first=${mac%%:*}
	[ $((0x$first & 1)) -eq 0 ] || return 1
	printf '%s\n' "$mac"
}

from_file() {
	f=$1
	[ -f "$f" ] || return 1
	text=$(grep -aoE '[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}' "$f" | head -n 1)
	if [ -n "$text" ]; then
		usable "$text"
		return
	fi
	set -- $(od -An -tx1 -N6 "$f")
	[ $# -eq 6 ] || return 1
	raw=$(printf '%s:%s:%s:%s:%s:%s' "$1" "$2" "$3" "$4" "$5" "$6")
	usable "$raw"
}

from_persist() {
	part=""
	i=0
	while [ "$i" -lt 20 ]; do
		if [ -e /dev/disk/by-partlabel/persist ]; then
			part=/dev/disk/by-partlabel/persist
			break
		fi
		i=$((i + 1))
		sleep 1
	done
	[ -n "$part" ] || return 1
	mkdir -p "$mnt"
	mount -o ro "$part" "$mnt" || return 1
	found=""
	for f in \
		"$mnt/bluetooth/.bid" \
		"$mnt/bluetooth/bt_nv.bin" \
		"$mnt/bluetooth/.bt_nv.bin" \
		"$mnt/bluetooth/bdaddr" \
		"$mnt/bluetooth/.bdaddr"
	do
		found=$(from_file "$f") && break
		found=""
	done
	umount "$mnt" || true
	[ -n "$found" ] || return 1
	printf '%s\n' "$found"
}

from_addr_file() {
	[ -s "$addr_file" ] || return 1
	line=$(grep -v '^[[:space:]]*#' "$addr_file" | tr -d '[:space:]' | head -c 17)
	usable "$line"
}

# Wi-Fi MAC + 1 (last octet, wrapping). Prefer the permanent address in case
# NetworkManager has already randomised the current one.
from_wifi() {
	i=0
	while [ "$i" -lt 20 ]; do
		for n in /sys/class/net/wl*; do
			[ -e "$n/address" ] || continue
			dev=${n##*/}
			mac=$(ip -o link show "$dev" 2>/dev/null | sed -n 's/.* permaddr \([0-9a-fA-F:]\{17\}\).*/\1/p')
			[ -n "$mac" ] || mac=$(cat "$n/address")
			mac=$(usable "$mac") || continue
			last=$(( (0x${mac##*:} + 1) & 0xff ))
			usable "$(printf '%s:%02X' "${mac%:*}" "$last")"
			return
		done
		i=$((i + 1))
		sleep 1
	done
	return 1
}

from_machine_id() {
	id=$(tr -d '[:space:]' < /etc/machine-id)
	b1=$(( (0x$(printf '%s' "$id" | cut -c1-2) | 0x02) & 0xfe ))
	printf '%02X:%s:%s:%s:%s:%s\n' \
		"$b1" \
		"$(printf '%s' "$id" | cut -c3-4)" \
		"$(printf '%s' "$id" | cut -c5-6)" \
		"$(printf '%s' "$id" | cut -c7-8)" \
		"$(printf '%s' "$id" | cut -c9-10)" \
		"$(printf '%s' "$id" | cut -c11-12)" | tr '[:lower:]' '[:upper:]'
}

addr=$(from_addr_file) || addr=$(from_persist) || addr=$(from_wifi) || addr=$(from_machine_id)
[ -n "$addr" ] || exit 1

i=0
while [ "$i" -lt 30 ]; do
	[ -d /sys/class/bluetooth/hci0 ] && break
	i=$((i + 1))
	sleep 1
done
[ -d /sys/class/bluetooth/hci0 ] || exit 1

# btmgmt waits out the full --timeout even after the command succeeds.
btmgmt --timeout 3 --index 0 power off >/dev/null 2>&1 || true
btmgmt --timeout 3 --index 0 public-addr "$addr" >/dev/null
btmgmt --timeout 3 --index 0 power on >/dev/null 2>&1 || true
