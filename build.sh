#!/usr/bin/env bash
# =============================================================================
#  build.sh — build a flashable Nura (formerly postmarketOS) image for the
#             Xiaomi POCO X3 Pro (codename: vayu, Nura device: xiaomi-vayu)
#
#  Uses pmbootstrap (fetched automatically, no system install needed) with a
#  private config + work dir inside ./build, so your ~/.config/pmbootstrap
#  setup is never touched.
#
#  Result: out/<name>/{boot.img,userdata.img,flash.sh,...} and a compressed
#          out/<name>.tar.zst that can be copied anywhere and flashed.
# =============================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE="xiaomi-vayu"

log()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

usage() {
	cat <<EOF
Usage: $0 [options]

Builds a Nura image for the Xiaomi POCO X3 Pro (vayu).
Defaults come from config.env, environment variables override them,
command line options override both.

Options:
  -c, --channel NAME     Nura channel: edge | v26.06 | ...   (default: edge)
  -p, --panel NAME       Display panel: tianma | huaxing      (default: tianma)
  -u, --ui NAME          UI: phosh | plasma-mobile | gnome-mobile |
                         sxmo-de-sway | console | ...          (default: phosh)
      --ui-extras        Install the UI's optional extras
  -P, --password PW      Initial user password                (default: 147147)
      --user NAME        Login user name                      (default: user)
      --hostname NAME    Hostname                             (default: nura-vayu)
  -e, --extra "a b c"    Extra packages (space separated)
  -f, --filesystem FS    ext4 | f2fs | btrfs | xfs            (default: ext4)
      --pmb-ref REF      pmbootstrap tag/branch, or "latest"
      --compress ALGO    zstd | xz | none                     (default: zstd)
  -o, --out DIR          Output directory                     (default: ./out)
      --clean            Remove the build dir (chroots, caches) before building
  -h, --help             Show this help

Example:
  $0 --panel huaxing --ui plasma-mobile --extra "htop vim"
EOF
}

# ----------------------------------------------------------------------------
# Argument parsing (sets env vars, config.env picks them up as overrides)
# ----------------------------------------------------------------------------
CLEAN=0
while [[ $# -gt 0 ]]; do
	case "$1" in
		-c|--channel)    export CHANNEL="$2"; shift 2 ;;
		-p|--panel)      export PANEL="$2"; shift 2 ;;
		-u|--ui)         export UI="$2"; shift 2 ;;
		--ui-extras)     export UI_EXTRAS=true; shift ;;
		-P|--password)   export NURA_PASSWORD="$2"; shift 2 ;;
		--user)          export NURA_USER="$2"; shift 2 ;;
		--hostname)      export HOSTNAME_NURA="$2"; shift 2 ;;
		-e|--extra)      export EXTRA_PACKAGES="$2"; shift 2 ;;
		-f|--filesystem) export FILESYSTEM="$2"; shift 2 ;;
		--pmb-ref)       export PMB_REF="$2"; shift 2 ;;
		--compress)      export COMPRESS="$2"; shift 2 ;;
		-o|--out)        export OUT_DIR="$2"; shift 2 ;;
		--clean)         CLEAN=1; shift ;;
		-h|--help)       usage; exit 0 ;;
		*) usage; die "Unknown option: $1" ;;
	esac
done

cd "$SCRIPT_DIR"
# shellcheck source=./config.env
source "$SCRIPT_DIR/config.env"

# Make relative paths absolute (pmbootstrap needs absolute paths)
BUILD_DIR="$(realpath -m "$BUILD_DIR")"
OUT_DIR="$(realpath -m "$OUT_DIR")"

# ----------------------------------------------------------------------------
# Validation
# ----------------------------------------------------------------------------
case "$PANEL" in
	tianma|huaxing) ;;
	*) die "PANEL must be 'tianma' or 'huaxing' (got '$PANEL')" ;;
esac
case "$FILESYSTEM" in
	ext4|f2fs|btrfs|xfs) ;;
	*) die "FILESYSTEM must be ext4, f2fs, btrfs or xfs (got '$FILESYSTEM')" ;;
esac
case "$COMPRESS" in
	zstd|xz|none) ;;
	*) die "COMPRESS must be zstd, xz or none (got '$COMPRESS')" ;;
esac
[[ "$CHANNEL" == "edge" || "$CHANNEL" =~ ^v[0-9]{2}\.[0-9]{2}$ ]] \
	|| die "CHANNEL must be 'edge' or a release like 'v26.06' (got '$CHANNEL')"
[[ -n "$NURA_PASSWORD" ]] || die "NURA_PASSWORD must not be empty"
[[ "$(uname -s)" == "Linux" ]] || die "pmbootstrap only runs on Linux"
[[ "$(id -u)" -ne 0 ]] || die "Do not run as root — pmbootstrap calls sudo itself"

need=(git python3 openssl kpartx losetup tar sudo sha256sum ps chroot)
[[ "$COMPRESS" == "zstd" ]] && need+=(zstd)
[[ "$COMPRESS" == "xz" ]] && need+=(xz)
missing=()
for p in "${need[@]}"; do command -v "$p" >/dev/null 2>&1 || missing+=("$p"); done
if [[ ${#missing[@]} -gt 0 ]]; then
	die "Missing programs: ${missing[*]}
    Debian/Ubuntu/Mint: sudo apt install git python3 openssl kpartx util-linux procps coreutils zstd xz-utils
    Arch/Manjaro:       sudo pacman -S git python openssl multipath-tools util-linux procps-ng zstd xz"
fi
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,10) else 1)' \
	|| die "Python >= 3.10 required"

# pmaports branch for the channel (see pmaports channels.cfg)
if [[ "$CHANNEL" == "edge" ]]; then PMAPORTS_BRANCH="main"; else PMAPORTS_BRANCH="$CHANNEL"; fi

PMB_DIR="$BUILD_DIR/pmbootstrap"
APORTS_DIR="$BUILD_DIR/pmaports"
WORK_DIR="$BUILD_DIR/work"
PMB_CFG="$BUILD_DIR/pmbootstrap_v3.cfg"
EXPORT_DIR="$BUILD_DIR/export"
STAMP="$(date -u +%Y%m%d-%H%M)"
IMAGE_NAME="nura-${DEVICE}-${PANEL}-${UI}-${CHANNEL}-${STAMP}"

log "Nura image for Xiaomi POCO X3 Pro (vayu)"
cat <<EOF
    channel    : $CHANNEL (pmaports branch: $PMAPORTS_BRANCH)
    panel      : $PANEL
    ui         : $UI (extras: $UI_EXTRAS)
    user       : $NURA_USER
    hostname   : $HOSTNAME_NURA
    filesystem : $FILESYSTEM
    extra pkgs : ${EXTRA_PACKAGES:-<none>}
    build dir  : $BUILD_DIR
    output     : $OUT_DIR/$IMAGE_NAME
EOF

# ----------------------------------------------------------------------------
# pmbootstrap wrapper + cleanup
# ----------------------------------------------------------------------------
pmb() {
	python3 "$PMB_DIR/pmbootstrap.py" --config "$PMB_CFG" --assume-yes "$@"
}

cleanup() {
	local rc=$?
	if [[ -f "$PMB_DIR/pmbootstrap.py" && -f "$PMB_CFG" && -d "$WORK_DIR" ]]; then
		pmb shutdown >/dev/null 2>&1 || true
	fi
	if [[ $rc -ne 0 ]]; then
		warn "Build failed (exit $rc)."
		if [[ -f "$WORK_DIR/log.txt" ]]; then
			warn "Last 60 lines of $WORK_DIR/log.txt:"
			tail -n 60 "$WORK_DIR/log.txt" >&2 || true
		fi
	fi
	exit $rc
}
trap cleanup EXIT

if [[ $CLEAN -eq 1 && -d "$BUILD_DIR" ]]; then
	log "Cleaning $BUILD_DIR"
	if [[ -f "$PMB_DIR/pmbootstrap.py" && -f "$PMB_CFG" && -d "$WORK_DIR" ]]; then
		pmb shutdown >/dev/null 2>&1 || true
	fi
	# chroots contain root-owned files
	sudo rm -rf "$BUILD_DIR"
fi
mkdir -p "$BUILD_DIR" "$OUT_DIR"

# ----------------------------------------------------------------------------
# 1) pmbootstrap
# ----------------------------------------------------------------------------
if [[ "$PMB_REF" == "latest" ]]; then
	PMB_REF="$(git ls-remote --tags --refs "$PMB_REPO" 2>/dev/null \
		| awk -F/ '{print $3}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1)"
	[[ -n "$PMB_REF" ]] || die "Could not determine latest pmbootstrap release tag"
fi
log "Fetching pmbootstrap $PMB_REF"
rm -rf "$PMB_DIR"
git clone -q --depth 1 --branch "$PMB_REF" "$PMB_REPO" "$PMB_DIR"

# ----------------------------------------------------------------------------
# 2) pmaports (package recipes incl. device-xiaomi-vayu)
#    pmbootstrap reads channels.cfg from origin/main, so that ref must exist
#    even when building a release channel.
# ----------------------------------------------------------------------------
log "Fetching pmaports ($PMAPORTS_BRANCH)"
if [[ ! -d "$APORTS_DIR/.git" ]]; then
	git init -q "$APORTS_DIR"
	git -C "$APORTS_DIR" remote add origin "$PMAPORTS_REPO"
fi
git -C "$APORTS_DIR" remote set-url origin "$PMAPORTS_REPO"
fetch_refs=("+$PMAPORTS_BRANCH:refs/remotes/origin/$PMAPORTS_BRANCH")
[[ "$PMAPORTS_BRANCH" != "main" ]] && fetch_refs+=("+main:refs/remotes/origin/main")
git -C "$APORTS_DIR" fetch -q --depth 1 origin "${fetch_refs[@]}"
git -C "$APORTS_DIR" checkout -q -f -B "$PMAPORTS_BRANCH" "origin/$PMAPORTS_BRANCH"
git -C "$APORTS_DIR" branch -q --set-upstream-to="origin/$PMAPORTS_BRANCH"

DEVICE_DIR="$(find "$APORTS_DIR/device" -maxdepth 2 -type d -name "device-$DEVICE" | head -n1)"
[[ -n "$DEVICE_DIR" ]] || die "device-$DEVICE not found in pmaports branch $PMAPORTS_BRANCH"
log "Device package: ${DEVICE_DIR#"$APORTS_DIR"/}"

# ----------------------------------------------------------------------------
# 3) Non-interactive pmbootstrap config (replaces 'pmbootstrap init')
# ----------------------------------------------------------------------------
extra_csv="none"
if [[ -n "${EXTRA_PACKAGES// /}" ]]; then
	extra_csv="$(echo "$EXTRA_PACKAGES" | xargs | tr ' ' ',')"
fi
ui_extras_cfg="False"; [[ "$UI_EXTRAS" == "true" ]] && ui_extras_cfg="True"

log "Writing pmbootstrap config"
cat > "$PMB_CFG" <<EOF
[pmbootstrap]
aports = $APORTS_DIR
work = $WORK_DIR
device = $DEVICE
kernel = $PANEL
ui = $UI
ui_extras = $ui_extras_cfg
user = $NURA_USER
hostname = $HOSTNAME_NURA
timezone = $TIMEZONE
locale = $LOCALE
extra_packages = $extra_csv
is_default_channel = False
build_pkgs_on_install = True
ssh_keys = False

[providers]

[mirrors]
EOF
chmod 600 "$PMB_CFG"

mkdir -p "$WORK_DIR"
if [[ ! -f "$WORK_DIR/version" ]]; then
	# Same marker 'pmbootstrap init' writes when creating a fresh work dir
	PYTHONPATH="$PMB_DIR" python3 -c 'import pmb.config as c; print(c.work_version)' \
		> "$WORK_DIR/version"
fi

# ----------------------------------------------------------------------------
# 4) Build + install rootfs image
# ----------------------------------------------------------------------------
log "Building image (this takes a while on first run)"
pmb --version
pmb install \
	--zap \
	--password "$NURA_PASSWORD" \
	--filesystem "$FILESYSTEM" \
	--sparse

# ----------------------------------------------------------------------------
# 5) Export boot.img + rootfs and assemble the flash kit
# ----------------------------------------------------------------------------
log "Exporting images"
rm -rf "$EXPORT_DIR"
mkdir -p "$EXPORT_DIR"
pmb export "$EXPORT_DIR"

KIT="$OUT_DIR/$IMAGE_NAME"
rm -rf "$KIT"
mkdir -p "$KIT"

copy_out() { # <src-in-export> <dst-name>
	local src="$EXPORT_DIR/$1"
	[[ -e "$src" ]] || die "Expected export file missing: $1"
	# Export entries are symlinks into root-owned chroots
	cp -L "$src" "$KIT/$2" 2>/dev/null || sudo cp -L "$src" "$KIT/$2"
}
copy_out "boot.img" "boot.img"
copy_out "$DEVICE.img" "userdata.img"
sudo chown "$(id -u):$(id -g)" "$KIT"/*.img

install -m 755 "$SCRIPT_DIR/flash.sh" "$KIT/flash.sh"

PMB_COMMIT="$(git -C "$PMB_DIR" rev-parse --short HEAD)"
APORTS_COMMIT="$(git -C "$APORTS_DIR" rev-parse --short HEAD)"
cat > "$KIT/build-info.txt" <<EOF
Nura image for Xiaomi POCO X3 Pro (vayu)
========================================
image name       : $IMAGE_NAME
built (UTC)      : $(date -u '+%Y-%m-%d %H:%M')
device           : $DEVICE
display panel    : $PANEL
channel          : $CHANNEL
ui               : $UI (extras: $UI_EXTRAS)
user             : $NURA_USER
initial password : (as set at build time — change it with 'passwd' after first boot)
hostname         : $HOSTNAME_NURA
timezone/locale  : $TIMEZONE / $LOCALE
filesystem       : $FILESYSTEM
extra packages   : ${EXTRA_PACKAGES:-none}
pmbootstrap      : $PMB_REF ($PMB_COMMIT)
pmaports         : $PMAPORTS_BRANCH ($APORTS_COMMIT)

Files:
  boot.img      -> fastboot flash boot     (kernel + initramfs, panel: $PANEL)
  userdata.img  -> fastboot flash userdata (root filesystem, Android sparse image)
  flash.sh      -> flashes both, see ./flash.sh --help
EOF

(cd "$KIT" && sha256sum boot.img userdata.img > SHA256SUMS)

# ----------------------------------------------------------------------------
# 6) Compress
# ----------------------------------------------------------------------------
case "$COMPRESS" in
	zstd)
		log "Compressing -> $IMAGE_NAME.tar.zst"
		tar -C "$OUT_DIR" -cf - "$IMAGE_NAME" | zstd -T0 -10 -q -o "$OUT_DIR/$IMAGE_NAME.tar.zst"
		ARCHIVE="$OUT_DIR/$IMAGE_NAME.tar.zst" ;;
	xz)
		log "Compressing -> $IMAGE_NAME.tar.xz"
		tar -C "$OUT_DIR" -cf - "$IMAGE_NAME" | xz -T0 -6 > "$OUT_DIR/$IMAGE_NAME.tar.xz"
		ARCHIVE="$OUT_DIR/$IMAGE_NAME.tar.xz" ;;
	none)
		ARCHIVE="" ;;
esac
if [[ -n "$ARCHIVE" ]]; then
	(cd "$OUT_DIR" && sha256sum "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256")
fi

# Machine-readable hints for CI
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
	{
		echo "image_name=$IMAGE_NAME"
		echo "kit_dir=$KIT"
		echo "archive=$ARCHIVE"
		echo "pmaports_commit=$APORTS_COMMIT"
		echo "pmbootstrap_ref=$PMB_REF"
	} >> "$GITHUB_OUTPUT"
fi

log "Done."
echo "    Flash kit : $KIT"
[[ -n "$ARCHIVE" ]] && echo "    Archive   : $ARCHIVE"
echo
echo "    Flash with: cd \"$KIT\" && ./flash.sh"
