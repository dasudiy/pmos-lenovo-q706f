#!/bin/sh
# Pause PipeWire playback before user.slice is frozen.
# Must be invoked from systemd-suspend.service ExecStartPre/Post, NOT from
# /usr/lib/systemd/system-sleep/: systemd 257 freezes user.slice first, and
# runuser/pactl against a frozen session blocks sleep/wake for tens of seconds.
#
# Qualcomm DPCM sets ignore_suspend, so a still-RUNNING PCM loops the last
# period through CS35L45 while the panel is off.

action=$1

timeout_pactl() {
	uid=$1
	shift
	runtime=/run/user/$uid
	[ -d "$runtime" ] || return 0
	user=$(awk -F: -v uid="$uid" '$3 == uid { print $1; exit }' /etc/passwd)
	[ -n "$user" ] || return 0

	timeout -s KILL 2 runuser -u "$user" -- env \
		XDG_RUNTIME_DIR="$runtime" \
		pactl "$@" >/dev/null 2>&1 || true
}

for_users() {
	cmd=$1
	for runtime in /run/user/[0-9]*; do
		[ -d "$runtime" ] || continue
		uid=${runtime##*/}
		timeout_pactl "$uid" suspend-sink @DEFAULT_SINK@ "$cmd" || true
		if [ "$cmd" = 0 ]; then
			timeout_pactl "$uid" set-sink-mute @DEFAULT_SINK@ 0 || true
		fi
	done
}

case "$action" in
pre)
	logger -t q706f-audio "pre: suspend default sink"
	for_users 1
	;;
post)
	logger -t q706f-audio "post: unsuspend default sink"
	for_users 0
	;;
esac

exit 0
