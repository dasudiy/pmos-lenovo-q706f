#!/bin/sh
# libcamera -> v4l2loopback forwarder. Usage: q706f-vcam.sh <back|front>
set -eu
. "/etc/q706f-vcam/$1.env"
W=${WIDTH:-1280}; H=${HEIGHT:-720}; F=${FPS:-30}
FLIPEL=""; [ -n "${FLIP:-}" ] && FLIPEL="$FLIP !"
# shellcheck disable=SC2086
exec gst-launch-1.0 -e libcamerasrc camera-name="$CAMERA" \
  ! video/x-raw,width=$W,height=$H,framerate=$F/1 ! videoconvert ! $FLIPEL \
  videoscale ! video/x-raw,format=YUY2,width=$W,height=$H,framerate=$F/1 \
  ! v4l2sink device="$DEVICE" sync=false
