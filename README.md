# Nura for the Xiaomi POCO X3 Pro (vayu)

🇩🇪 [Deutsche Version](README.de.md)

Build and flash kit for [Nura](https://nura.eco) (known as *postmarketOS* until September 2026) on the
**Xiaomi POCO X3 Pro** – codename `vayu`, Nura device name `xiaomi-vayu`.

- `build.sh` builds a ready-to-flash image (`boot.img` + `userdata.img`) with pmbootstrap
- `flash.sh` flashes it to the phone via fastboot
- `.github/workflows/build.yml` builds it in GitHub Actions with one click and publishes a release

> ⚠️ `xiaomi-vayu` is a **testing** device in Nura (mainline kernel `linux-postmarketos-qcom-sm8150`).
> Not everything works (camera, possibly modem/audio etc.) – see the
> [Nura wiki](https://wiki.nura.eco/wiki/Xiaomi_POCO_X3_Pro_(xiaomi-vayu)) for the current status.
> Flashing `userdata` **erases everything** on the phone (Android, Ubuntu Touch, your data).

---

## Contents

```
.
├── build.sh                    # build the image
├── flash.sh                    # flash the image (also copied into every flash kit)
├── config.env                  # default build settings
├── .github/workflows/build.yml # GitHub Actions: one-click build
├── README.md                   # English
└── README.de.md                # German
```

## 1. Find out your display panel (important!)

The POCO X3 Pro ships with one of two displays. Each needs its own kernel device tree –
with the wrong panel the phone boots, but the **screen stays black**.

| Panel          | Kernel cmdline entry               | Build option      |
|----------------|------------------------------------|-------------------|
| Tianma         | `dsi_j20s_36_02_0a_video_display`  | `--panel tianma`  |
| Huaxing / CSOT | `dsi_j20s_42_02_0b_video_display`  | `--panel huaxing` |

Check while Android / LineageOS / Ubuntu Touch is still installed (adb shell or terminal):

```bash
cat /proc/cmdline | grep -o 'dsi_j20s[^ ]*'
# or from your PC:  adb shell cat /proc/cmdline | grep -o 'dsi_j20s[^ ]*'
```

If in doubt, build `panel: both` in GitHub Actions and try both `boot.img` files
(`./flash.sh --boot-only` only swaps the kernel, your data stays).

## 2. Requirements

- Unlocked bootloader (Xiaomi Mi Unlock)
- Recommended: flash the latest stock firmware (MIUI 14) once beforehand – some modem/DSP firmware
  is read from the Android partitions
- A PC with `fastboot` (Mint/Ubuntu: `sudo apt install fastboot`, Arch/Manjaro: `sudo pacman -S android-tools`)

For local builds additionally (Linux, x86_64 or aarch64, a user with `sudo`, ~15 GB free):

```bash
# Debian / Ubuntu / Mint
sudo apt install git python3 openssl kpartx util-linux procps coreutils zstd xz-utils
# Arch / Manjaro
sudo pacman -S git python openssl multipath-tools util-linux procps-ng zstd xz
```

pmbootstrap does **not** need to be installed – `build.sh` fetches the latest release itself and
uses its own config and work directory under `./build`. An existing `~/.config/pmbootstrap_v3.cfg`
is never touched.

## 3. Build locally

```bash
cd ~/nura            # or /home/developer/nura
./build.sh --panel tianma                       # Phosh, edge, default PIN 147147
./build.sh --panel huaxing --ui plasma-mobile
./build.sh --panel tianma --extra "htop vim tmux" --password 2468
./build.sh --help                               # all options
```

The first build takes 20–60 minutes depending on your machine (downloading packages, setting up
chroots); later builds are faster because `./build` is kept as a cache (`--clean` resets everything).
pmbootstrap will ask for your `sudo` password along the way.

Result in `out/`:

```
out/
├── nura-xiaomi-vayu-tianma-phosh-edge-20261030-0812/
│   ├── boot.img          # kernel + initramfs (panel specific)
│   ├── userdata.img      # root filesystem (Android sparse image)
│   ├── flash.sh
│   ├── build-info.txt
│   └── SHA256SUMS
├── nura-xiaomi-vayu-tianma-phosh-edge-20261030-0812.tar.zst
└── nura-xiaomi-vayu-tianma-phosh-edge-20261030-0812.tar.zst.sha256
```

### Settings

Defaults live in `config.env`. Precedence: `config.env` < environment variable < command line.

| Variable         | Option          | Default           | Meaning |
|------------------|-----------------|-------------------|---------|
| `PANEL`          | `--panel`       | `tianma`          | `tianma` or `huaxing` |
| `UI`             | `--ui`          | `phosh`           | `phosh`, `plasma-mobile`, `gnome-mobile`, `sxmo-de-sway`, `console` |
| `CHANNEL`        | `--channel`     | `edge`            | `edge` (rolling) or a release, e.g. `v26.06` |
| `UI_EXTRAS`      | `--ui-extras`   | `false`           | optional UI extra packages |
| `NURA_PASSWORD`  | `--password`    | `147147`          | initial password / lock screen PIN |
| `NURA_USER`      | `--user`        | `user`            | user name |
| `HOSTNAME_NURA`  | `--hostname`    | `nura-vayu`       | hostname |
| `EXTRA_PACKAGES` | `--extra`       | –                 | additional packages, space separated |
| `FILESYSTEM`     | `--filesystem`  | `ext4`            | `ext4`, `f2fs`, `btrfs`, `xfs` |
| `TIMEZONE`       | –               | `Europe/Berlin`   | time zone |
| `LOCALE`         | –               | `de_DE.UTF-8`     | language (e.g. `en_US.UTF-8`) |
| `PMB_REF`        | `--pmb-ref`     | `latest`          | pmbootstrap version (tag/branch) |
| `COMPRESS`       | `--compress`    | `zstd`            | `zstd`, `xz`, `none` |

## 4. Flashing

1. Power off the phone, hold **Volume Down + Power** until "FASTBOOT" appears, connect USB.
2. Flash:

```bash
# straight from the kit directory
cd out/nura-xiaomi-vayu-tianma-phosh-edge-*/ && ./flash.sh

# or directly from the archive (e.g. downloaded from a GitHub release)
./flash.sh ~/Downloads/nura-xiaomi-vayu-tianma-phosh-edge-20261030-0812.tar.zst
```

`flash.sh` verifies checksums, waits for the phone, refuses anything that is not a POCO X3 Pro
(`product: vayu`), asks before wiping, then flashes `boot` and `userdata`.

| Option          | Effect |
|-----------------|--------|
| `--boot-only`   | only `boot.img` (switch kernel/panel, keep data) |
| `--rootfs-only` | only `userdata.img` |
| `--erase-dtbo`  | erase the Android `dtbo` partition first – if the phone does not boot / bootloops |
| `--no-reboot`   | stay in fastboot afterwards |
| `-s SERIAL`     | pick a specific device when several are connected |
| `-y`            | no confirmation prompt |

The first boot takes 1–2 minutes. Log in with the PIN (default `147147`) and run `passwd`
right away. Over USB the phone also shows up as a network device
(`ssh user@172.16.42.1`, if SSH is installed/enabled).

Back to Android: flash a Xiaomi fastboot ROM with MiFlash or its `flash_all.sh`.

## 5. One-click builds with GitHub Actions

### One-time setup

```bash
cd ~/nura
git init -b main
git add .
git commit -m "Nura build kit for POCO X3 Pro (vayu)"
```

Then either with the GitHub CLI:

```bash
gh repo create nura-vayu --public --source . --push
```

or create an empty repository at https://github.com/new (no README/.gitignore/license) and push via SSH:

```bash
git remote add origin git@github.com:<user>/nura-vayu.git
git push -u origin main
```

Under **Settings → Actions → General → Workflow permissions** allow "Read and write permissions"
so the release job can create releases.

Optionally create a secret `NURA_PASSWORD` under **Settings → Secrets and variables → Actions**.
It is then used instead of the input field and does not show up in the run parameters.

### Start a new build

1. Open **Actions → "Build Nura image (POCO X3 Pro / vayu)"** in the repository
2. Click **Run workflow**
3. Pick the options and start:

| Input            | Meaning |
|------------------|---------|
| `panel`          | `both` (default, builds tianma **and** huaxing in parallel), `tianma`, `huaxing` |
| `ui`             | user interface |
| `channel`        | `edge` or a release |
| `ui_extras`      | UI extra packages |
| `extra_packages` | additional packages |
| `filesystem`     | filesystem |
| `password`       | initial PIN (ignored if the secret `NURA_PASSWORD` exists) |
| `runner`         | `ubuntu-24.04-arm` = native aarch64, approx. 30–60 min · `ubuntu-24.04` = x86 with QEMU emulation, much slower |
| `release`        | publish the result as a GitHub release |

Or from the command line:

```bash
gh workflow run build.yml -f panel=tianma -f ui=phosh -f channel=edge
gh run watch
```

### Output

- Every build job uploads `nura-xiaomi-vayu-<panel>-<ui>-<channel>-<date>.tar.zst` (+ `.sha256`)
  as an **artifact** (kept for 14 days, download under "Artifacts" in the run).
- With `release: true` a **release** is created as well (tag `nura-vayu-<ui>-<channel>-<date>-r<run>`,
  a pre-release for `edge`) containing all archives.
- If a build fails, `pmbootstrap-log-<panel>` with the full pmbootstrap log is uploaded.

`flash.sh` can take an artifact ZIP directly: `./flash.sh nura-xiaomi-vayu-....zip`.

Automatic weekly builds: enable the commented-out `schedule:` block in the workflow.

> Notes: the arm64 runners (`ubuntu-24.04-arm`) are free for public repositories; for private
> repositories choose `ubuntu-24.04` if needed. Release assets are limited to 2 GB each – with
> Phosh/zstd the archive is normally well below that.

## 6. Troubleshooting

| Problem | Solution |
|---------|----------|
| Black screen, but the phone is running (warm, USB network appears) | wrong panel → build with the other `--panel` and run `./flash.sh --boot-only` |
| Bootloop / drops back to fastboot | `./flash.sh --boot-only --erase-dtbo` |
| `No fastboot device found` | different cable/USB 2 port, udev rules (`android-udev-rules`) or try `sudo fastboot devices` |
| `product` is not `vayu` | wrong device – the script aborts on purpose |
| Build: `device-xiaomi-vayu not found` | device missing in the selected channel → use `edge` |
| Build fails inside pmbootstrap | check `build/work/log.txt` (local) or the `pmbootstrap-log-*` artifact; `./build.sh --clean` |
| Package from `--extra` not found | check the name on [pkgs.nura.eco](https://pkgs.nura.eco) / [pkgs.alpinelinux.org](https://pkgs.alpinelinux.org) |

## How it works

`build.sh` replaces the interactive `pmbootstrap init` with a generated config:

1. Clone pmbootstrap (latest release tag) into `build/pmbootstrap`
2. Fetch pmaports for the channel (`edge` → branch `main`, `v26.06` → `v26.06`) into `build/pmaports`
3. Write `build/pmbootstrap_v3.cfg`: `device = xiaomi-vayu`, `kernel = <panel>`, UI, user etc.
4. `pmbootstrap install --sparse` builds the rootfs and `boot.img` (fastboot method per `deviceinfo`)
5. `pmbootstrap export` → copy `boot.img` + `xiaomi-vayu.img` (as `userdata.img`) into the flash kit,
   create checksums + `build-info.txt`, compress with zstd

This is the same as the official `pmbootstrap init` → `pmbootstrap install` →
`pmbootstrap flasher flash_rootfs` / `flash_kernel` route, just reproducible and without prompts.
