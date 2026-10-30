#!/usr/bin/env bash
# =============================================================================
#  flash.sh — flash a Nura image onto the Xiaomi POCO X3 Pro (vayu) via fastboot
#
#  Works from:
#    * an extracted flash kit (boot.img + userdata.img next to this script)
#    * a downloaded archive:  ./flash.sh nura-xiaomi-vayu-....tar.zst
#    * a directory:           ./flash.sh path/to/kit/
#
#  Phone preparation: bootloader unlocked, power off, then hold
#  Volume Down + Power until "FASTBOOT" appears, connect USB.
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
	cat <<EOF
Usage: $0 [options] [kit-dir | archive.tar.zst | archive.tar.xz]

Flashes Nura onto a Xiaomi POCO X3 Pro (vayu) in fastboot mode.
WARNING: flashing userdata ERASES ALL DATA on the phone (Android/Ubuntu Touch).

Options:
  --boot-only      Only flash boot.img (kernel update, keeps your data)
  --rootfs-only    Only flash userdata.img
  --erase-dtbo     Erase the Android dtbo partition first
                   (try this if the phone does not boot / bootloops)
  --no-reboot      Stay in fastboot after flashing
  -s, --serial SN  Use the fastboot device with this serial
  -y, --yes        Do not ask for confirmation
  -h, --help       Show this help

Examples:
  $0                                   # kit next to this script
  $0 ~/Downloads/nura-xiaomi-vayu-tianma-phosh-edge-20261030-0812.tar.zst
  $0 --boot-only
EOF
}

DO_BOOT=1; DO_ROOTFS=1; ERASE_DTBO=0; REBOOT=1; ASSUME_YES=0; SERIAL=""; SRC=""
while [[ $# -gt 0 ]]; do
	case "$1" in
		--boot-only)   DO_ROOTFS=0; shift ;;
		--rootfs-only) DO_BOOT=0; shift ;;
		--erase-dtbo)  ERASE_DTBO=1; shift ;;
		--no-reboot)   REBOOT=0; shift ;;
		-s|--serial)   SERIAL="$2"; shift 2 ;;
		-y|--yes)      ASSUME_YES=1; shift ;;
		-h|--help)     usage; exit 0 ;;
		-*)            usage; die "Unknown option: $1" ;;
		*)             SRC="$1"; shift ;;
	esac
done
[[ $DO_BOOT -eq 1 || $DO_ROOTFS -eq 1 ]] || die "--boot-only and --rootfs-only exclude each other"

command -v fastboot >/dev/null 2>&1 || die "fastboot not found.
    Debian/Ubuntu/Mint: sudo apt install fastboot   (or android-sdk-platform-tools)
    Arch/Manjaro:       sudo pacman -S android-tools"

FB=(fastboot)
[[ -n "$SERIAL" ]] && FB+=(-s "$SERIAL")

# ----------------------------------------------------------------------------
# Locate images (kit dir or archive)
# ----------------------------------------------------------------------------
TMP=""
cleanup() { [[ -n "$TMP" && -d "$TMP" ]] && rm -rf "$TMP"; return 0; }
trap cleanup EXIT

[[ -z "$SRC" ]] && SRC="$SCRIPT_DIR"
if [[ -f "$SRC" ]]; then
	TMP="$(mktemp -d "${TMPDIR:-/tmp}/nura-flash.XXXXXX")"
	log "Extracting $(basename "$SRC")"
	case "$SRC" in
		*.tar.zst|*.tzst) command -v zstd >/dev/null || die "zstd not installed"
		                  zstd -dc -T0 "$SRC" | tar -C "$TMP" -xf - ;;
		*.tar.xz|*.txz)   tar -C "$TMP" -xJf "$SRC" ;;
		*.tar)            tar -C "$TMP" -xf "$SRC" ;;
		*.zip)            command -v unzip >/dev/null || die "unzip not installed"
		                  unzip -q "$SRC" -d "$TMP"
		                  # GitHub artifact zip may contain the .tar.zst
		                  inner="$(find "$TMP" -maxdepth 1 -name '*.tar.zst' | head -n1)"
		                  if [[ -n "$inner" ]]; then zstd -dc -T0 "$inner" | tar -C "$TMP" -xf -; rm -f "$inner"; fi ;;
		*) die "Unknown archive type: $SRC" ;;
	esac
	SRC="$TMP"
fi
[[ -d "$SRC" ]] || die "Not a directory or archive: $SRC"

BOOT_IMG="$(find "$SRC" -maxdepth 2 -name boot.img -type f | head -n1)"
[[ -n "$BOOT_IMG" ]] || die "boot.img not found in $SRC"
KIT="$(dirname "$BOOT_IMG")"
ROOT_IMG="$KIT/userdata.img"
[[ $DO_ROOTFS -eq 0 || -f "$ROOT_IMG" ]] || die "userdata.img not found in $KIT"

if [[ -f "$KIT/build-info.txt" ]]; then
	echo
	sed -n '1,16p' "$KIT/build-info.txt"
	echo
fi

if [[ -f "$KIT/SHA256SUMS" ]]; then
	log "Verifying checksums"
	(cd "$KIT" && sha256sum --quiet -c SHA256SUMS) || die "Checksum mismatch — download again"
fi

# ----------------------------------------------------------------------------
# Wait for the phone in fastboot mode and sanity-check it
# ----------------------------------------------------------------------------
log "Waiting for phone in fastboot mode (Volume Down + Power, USB connected)..."
fb_present() { local o; o="$("${FB[@]}" devices 2>/dev/null || true)"; [[ "$o" == *fastboot* ]]; }
for _ in $(seq 1 60); do
	fb_present && break
	sleep 1
done
fb_present || die "No fastboot device found. Check cable/udev rules (try: sudo fastboot devices)."

getvar() {
	local o
	o="$("${FB[@]}" getvar "$1" 2>&1 || true)"
	awk -F': *' -v k="$1" '$1==k && !found {print $2; found=1}' <<<"$o" | tr -d '\r'
}

PRODUCT="$(getvar product)"
UNLOCKED="$(getvar unlocked)"
log "Found device: product=${PRODUCT:-?} unlocked=${UNLOCKED:-?}"

case "$PRODUCT" in
	vayu|bhima) ;;
	*) die "This is not a POCO X3 Pro (product '$PRODUCT'). Aborting to protect your device." ;;
esac
if [[ "$UNLOCKED" != "yes" ]]; then
	warn "Bootloader does not report 'unlocked: yes' (got '${UNLOCKED:-?}')."
	warn "Flashing will fail on a locked bootloader (use Xiaomi's Mi Unlock tool first)."
fi

# ----------------------------------------------------------------------------
# Confirm + flash
# ----------------------------------------------------------------------------
echo
echo "About to flash:"
[[ $ERASE_DTBO -eq 1 ]] && echo "  erase  dtbo"
[[ $DO_BOOT -eq 1 ]]    && echo "  boot     <- $(basename "$BOOT_IMG")"
[[ $DO_ROOTFS -eq 1 ]]  && echo "  userdata <- $(basename "$ROOT_IMG")  ($(du -h "$ROOT_IMG" | cut -f1))"
if [[ $DO_ROOTFS -eq 1 ]]; then
	echo
	warn "This ERASES ALL DATA on the phone (Android / Ubuntu Touch / your files)."
fi
if [[ $ASSUME_YES -eq 0 ]]; then
	read -r -p "Type 'yes' to continue: " answer
	[[ "$answer" == "yes" ]] || die "Aborted."
fi

if [[ $ERASE_DTBO -eq 1 ]]; then
	log "Erasing dtbo"
	"${FB[@]}" erase dtbo
fi
if [[ $DO_BOOT -eq 1 ]]; then
	log "Flashing boot"
	"${FB[@]}" flash boot "$BOOT_IMG"
fi
if [[ $DO_ROOTFS -eq 1 ]]; then
	log "Flashing userdata (takes a few minutes)"
	"${FB[@]}" flash userdata "$ROOT_IMG"
fi

if [[ $REBOOT -eq 1 ]]; then
	log "Rebooting"
	"${FB[@]}" reboot
fi

log "Done."
cat <<EOF

First boot can take 1-2 minutes. Login/unlock PIN = the password set at
build time (default: 147147). Change it afterwards:  passwd

Black screen but phone is warm/USB network appears? -> wrong display panel,
rebuild with the other --panel (tianma <-> huaxing) and run: $0 --boot-only
Bootloop? -> try: $0 --erase-dtbo --boot-only
EOF
