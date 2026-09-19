#!/bin/sh
# NEUTRALIZED 2026-09-19: do NOT re-enable unattended.
# The GPU DPMS power-off (niri msg action power-off-monitors) and DDC/CI
# standby both failed to wake reliably on this box (nvidia-drm modeset=1):
# monitor wake cycle -> "NVKMS GEM: Failed to allocate" / DPMS stuck ->
# permanently black display, hard reset required. This cost the user two
# hard resets. See config.kdl comment and the niri memory entry.
#
# If a safe method is found later (e.g. DDC standby proven across several
# unattended cycles, or a driver that fixes NVKMS re-init), re-enable only
# with the user's explicit approval.
echo "idle.sh is intentionally a no-op (display power-saving disabled)." >&2
exit 0
