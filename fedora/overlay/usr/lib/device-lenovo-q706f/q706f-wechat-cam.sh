#!/bin/sh
# Usage: q706f-wechat-cam.sh [front|back] [wechat args...]   (default: front)
# Only one camera can stream at a time (both sensors share msm_csid0).
cam=front
case "${1:-}" in front|back) cam=$1; shift;; esac
other=back; [ "$cam" = back ] && other=front
systemctl --user stop "q706f-vcam@$other.service"
systemctl --user start "q706f-vcam@$cam.service" || exit 1
sleep 2
flatpak run com.tencent.WeChat "$@"; rc=$?
systemctl --user stop "q706f-vcam@$cam.service"
exit $rc
