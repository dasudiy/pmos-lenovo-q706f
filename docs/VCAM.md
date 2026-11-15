# Virtual V4L2 cameras (v4l2loopback) for WebRTC / Flatpak WeChat

WeChat (Flatpak, WebRTC video_capture_v4l2) scans /dev/video0-63 and only keeps
nodes with V4L2_CAP_VIDEO_CAPTURE; it cannot use libcamera. We forward
libcamera -> v4l2loopback (/dev/video40 back, /dev/video41 front).

* Module: v4l2loopback 0.15.4 built out-of-tree with
  `fedora/scripts/build-v4l2loopback.sh` against the device kernel tree, signed
  with that kernel's module key. Set `KERNEL_TREE` and `V4L2LB_SRC` to the
  prepared source trees, put the kernel toolchain on `PATH`, and optionally
  set `OUT` for the module staging directory. The module is installed to /usr/lib/modules/$KVER/extra
  (binary not tracked; rebuild per kernel).
* Options: etc/modprobe.d/q706f-v4l2loopback.conf, autoload via modules-load.d.
* exclusive_caps=1 is not strictly needed by WebRTC, but without a producer the
  node would advertise OUTPUT|CAPTURE and Chromium-based apps may list it
  wrongly; with it, the producer must already be streaming (no start-on-open).
* Producer: `systemctl --user start q706f-vcam@back q706f-vcam@front`
  (gst libcamerasrc, needs libcamera-gstreamer). Config in /etc/q706f-vcam/*.env.
  While running it holds the camera exclusively (PipeWire/other apps can't use it)
  and costs soft-ISP CPU, so prefer `q706f-wechat-cam.sh` (on-demand around WeChat)
  over `enable`.

## Single camera at a time
libcamera's simple pipeline routes both sensors (ov13b10 via csiphy2, ov8856)
to `msm_csid0`; while one streams the other fails with
"Failed to setup link 'msm_csiphy2'[1] -> 'msm_csid0'[0]: Device or resource busy"
(csid1-3 stay unused). So only one vcam instance can run. Drop-ins
`q706f-vcam@{front,back}.service.d/10-exclusive.conf` set mutual Conflicts=,
and `q706f-wechat-cam.sh [front|back]` (default front) starts just one.

Measured (1280x720 YUY2, single camera, Oct 2026): front ~68% of one core,
~24 fps read; back ~127% of one core. No rotation needed: both outputs are
upright landscape with the tablet held landscape. CmaFree drops to ~2.5 MB of
256 MB while streaming (most of it is libcamera's full-res buffers).
