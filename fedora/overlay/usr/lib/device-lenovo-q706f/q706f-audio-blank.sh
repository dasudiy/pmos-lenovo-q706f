#!/bin/sh
# User-session helper: pause speakers when the panel blanks or logind is
# preparing sleep. Runs before systemd freezes user.slice.

runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
lock="$runtime/q706f-audio-blank.lock"
mkdir -p "$runtime"
exec 9>"$lock"
if command -v flock >/dev/null 2>&1; then
	flock -n 9 || exit 0
fi

paused=0

pause_sink() {
	[ "$paused" = 1 ] && return 0
	pactl suspend-sink @DEFAULT_SINK@ 1 >/dev/null 2>&1 || true
	paused=1
}

resume_sink() {
	[ "$paused" = 0 ] && return 0
	pactl suspend-sink @DEFAULT_SINK@ 0 >/dev/null 2>&1 || true
	pactl set-sink-mute @DEFAULT_SINK@ 0 >/dev/null 2>&1 || true
	paused=0
}

panel_off() {
	for f in /sys/class/drm/card*-DSI-1/dpms; do
		[ -f "$f" ] || continue
		v=$(cat "$f" 2>/dev/null)
		[ "$v" = On ] || return 0
	done
	return 1
}

preparing_sleep() {
	busctl get-property org.freedesktop.login1 /org/freedesktop/login1 \
		org.freedesktop.login1.Manager PreparingForSleep 2>/dev/null | grep -q true
}

n=0
while ! pactl info >/dev/null 2>&1; do
	n=$((n + 1))
	[ "$n" -gt 60 ] && break
	sleep 1
done

while :; do
	if panel_off || preparing_sleep; then
		pause_sink
	else
		resume_sink
	fi
	sleep 0.3
done
