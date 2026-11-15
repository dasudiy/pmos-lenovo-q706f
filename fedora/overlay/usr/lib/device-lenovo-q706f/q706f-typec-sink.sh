#!/bin/sh
# Prefer sink so a charger attaches as a power sink. A USB stick is a sink
# itself, so the port must be allowed to fall back to source/host.
# Forcing sink on every source attach disconnects the stick in a loop.
p=/sys/class/typec/port0
[ -d "$p" ] || exit 0
echo sink > "$p/preferred_role" 2>/dev/null || exit 0

# Only the boot-time case: a charger already attached, port stuck as source,
# and no USB peripheral enumerated. One renegotiation, then leave it dual.
role=$(cat "$p/power_role" 2>/dev/null)
case "$role" in
\[source\]*) ;;
*) exit 0 ;;
esac
[ -d "$p-partner" ] || exit 0
sleep 2
found=0
for d in /sys/bus/usb/devices/[0-9]*-[0-9]*; do
	[ -e "$d/idVendor" ] || continue
	vendor=$(cat "$d/idVendor" 2>/dev/null)
	[ "$vendor" = "1d6b" ] && continue
	found=1
	break
done
[ "$found" = 1 ] && exit 0
[ -e /run/q706f-typec-sink.lock ] && exit 0
touch /run/q706f-typec-sink.lock
echo sink > "$p/port_type"
sleep 2
echo dual > "$p/port_type"
rm -f /run/q706f-typec-sink.lock
exit 0
