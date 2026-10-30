# Nura für das Xiaomi POCO X3 Pro (vayu)

Build- und Flash-Kit für [Nura](https://nura.eco) (bis September 2026 *postmarketOS*) auf dem
**Xiaomi POCO X3 Pro** – Codename `vayu`, Nura-Gerätename `xiaomi-vayu`.

- `build.sh` baut ein fertiges, flashbares Image (`boot.img` + `userdata.img`) mit pmbootstrap
- `flash.sh` flasht es per fastboot aufs Telefon
- `.github/workflows/build.yml` baut per Klick in GitHub Actions und veröffentlicht ein Release

> ⚠️ `xiaomi-vayu` ist in Nura ein **testing**-Gerät (Mainline-Kernel `linux-postmarketos-qcom-sm8150`).
> Nicht alles funktioniert (Kamera, ggf. Modem/Audio usw.) – aktueller Stand im
> [Nura-Wiki](https://wiki.nura.eco/wiki/Xiaomi_POCO_X3_Pro_(xiaomi-vayu)).
> Das Flashen von `userdata` **löscht alles** auf dem Telefon (Android, Ubuntu Touch, Daten).

---

## Inhalt

```
.
├── build.sh                    # Image bauen
├── flash.sh                    # Image flashen (wird auch ins Flash-Kit kopiert)
├── config.env                  # Standardwerte für den Build
├── .github/workflows/build.yml # GitHub Actions: Build per Klick
└── README.md
```

## 1. Display-Panel herausfinden (wichtig!)

Das POCO X3 Pro gibt es mit zwei Displays. Jedes braucht einen eigenen Kernel-Device-Tree –
mit dem falschen Panel bootet das Telefon, aber der **Bildschirm bleibt schwarz**.

| Panel          | Kernel-Cmdline-Eintrag             | Build-Option     |
|----------------|------------------------------------|------------------|
| Tianma         | `dsi_j20s_36_02_0a_video_display`  | `--panel tianma` |
| Huaxing / CSOT | `dsi_j20s_42_02_0b_video_display`  | `--panel huaxing`|

Prüfen, solange noch Android / LineageOS / Ubuntu Touch drauf ist (adb-Shell oder Terminal):

```bash
cat /proc/cmdline | grep -o 'dsi_j20s[^ ]*'
# oder vom PC:  adb shell cat /proc/cmdline | grep -o 'dsi_j20s[^ ]*'
```

Im Zweifel einfach in GitHub Actions `panel: both` bauen und beide `boot.img` ausprobieren
(`./flash.sh --boot-only` wechselt nur den Kernel, die Daten bleiben).

## 2. Voraussetzungen

- Bootloader entsperrt (Xiaomi Mi Unlock)
- Empfohlen: vorher einmal die letzte Stock-Firmware (MIUI 14) geflasht haben – Modem-/DSP-Firmware
  wird teils von den Android-Partitionen gelesen
- PC mit `fastboot` (Mint/Ubuntu: `sudo apt install fastboot`, Arch/Manjaro: `sudo pacman -S android-tools`)

Für lokale Builds zusätzlich (Linux, x86_64 oder aarch64, Benutzer mit `sudo`, ~15 GB frei):

```bash
# Debian / Ubuntu / Mint
sudo apt install git python3 openssl kpartx util-linux procps coreutils zstd xz-utils
# Arch / Manjaro
sudo pacman -S git python openssl multipath-tools util-linux procps-ng zstd xz
```

pmbootstrap muss **nicht** installiert sein – `build.sh` holt sich die aktuelle Release-Version
selbst und arbeitet mit eigener Config und eigenem Work-Verzeichnis unter `./build`.
Eine vorhandene `~/.config/pmbootstrap_v3.cfg` wird nicht angefasst.

## 3. Lokal bauen

```bash
cd ~/nura            # bzw. /home/developer/nura
./build.sh --panel tianma                       # Phosh, edge, Standard-PIN 147147
./build.sh --panel huaxing --ui plasma-mobile
./build.sh --panel tianma --extra "htop vim tmux" --password 2468
./build.sh --help                               # alle Optionen
```

Der erste Build dauert je nach Rechner 20–60 Minuten (Pakete laden, Chroots aufsetzen);
Folge-Builds sind schneller, weil `./build` als Cache erhalten bleibt (`--clean` setzt alles zurück).
pmbootstrap fragt zwischendurch nach dem `sudo`-Passwort.

Ergebnis in `out/`:

```
out/
├── nura-xiaomi-vayu-tianma-phosh-edge-20261030-0812/
│   ├── boot.img          # Kernel + initramfs (panelspezifisch)
│   ├── userdata.img      # Root-Dateisystem (Android-Sparse-Image)
│   ├── flash.sh
│   ├── build-info.txt
│   └── SHA256SUMS
├── nura-xiaomi-vayu-tianma-phosh-edge-20261030-0812.tar.zst
└── nura-xiaomi-vayu-tianma-phosh-edge-20261030-0812.tar.zst.sha256
```

### Einstellungen

Standardwerte stehen in `config.env`. Reihenfolge: `config.env` < Umgebungsvariable < Kommandozeile.

| Variable         | Option          | Standard          | Bedeutung |
|------------------|-----------------|-------------------|-----------|
| `PANEL`          | `--panel`       | `tianma`          | `tianma` oder `huaxing` |
| `UI`             | `--ui`          | `phosh`           | `phosh`, `plasma-mobile`, `gnome-mobile`, `sxmo-de-sway`, `console` |
| `CHANNEL`        | `--channel`     | `edge`            | `edge` (rolling) oder Release, z. B. `v26.06` |
| `UI_EXTRAS`      | `--ui-extras`   | `false`           | optionale UI-Zusatzpakete |
| `NURA_PASSWORD`  | `--password`    | `147147`          | Start-Passwort / Sperrbildschirm-PIN |
| `NURA_USER`      | `--user`        | `user`            | Benutzername |
| `HOSTNAME_NURA`  | `--hostname`    | `nura-vayu`       | Hostname |
| `EXTRA_PACKAGES` | `--extra`       | –                 | zusätzliche Pakete, durch Leerzeichen getrennt |
| `FILESYSTEM`     | `--filesystem`  | `ext4`            | `ext4`, `f2fs`, `btrfs`, `xfs` |
| `TIMEZONE`       | –               | `Europe/Berlin`   | Zeitzone |
| `LOCALE`         | –               | `de_DE.UTF-8`     | Sprache |
| `PMB_REF`        | `--pmb-ref`     | `latest`          | pmbootstrap-Version (Tag/Branch) |
| `COMPRESS`       | `--compress`    | `zstd`            | `zstd`, `xz`, `none` |

## 4. Flashen

1. Telefon ausschalten, **Leiser + Power** halten bis „FASTBOOT“ erscheint, per USB anschließen.
2. Flashen:

```bash
# direkt aus dem Kit-Verzeichnis
cd out/nura-xiaomi-vayu-tianma-phosh-edge-*/ && ./flash.sh

# oder direkt mit dem Archiv (z. B. aus einem GitHub-Release)
./flash.sh ~/Downloads/nura-xiaomi-vayu-tianma-phosh-edge-20261030-0812.tar.zst
```

`flash.sh` prüft Checksummen, wartet auf das Telefon, verweigert alles, was kein POCO X3 Pro
(`product: vayu`) ist, fragt vor dem Löschen nach und flasht dann `boot` und `userdata`.

| Option          | Wirkung |
|-----------------|---------|
| `--boot-only`   | nur `boot.img` (Kernel/Panel wechseln, Daten bleiben) |
| `--rootfs-only` | nur `userdata.img` |
| `--erase-dtbo`  | Android-`dtbo` vorher löschen – falls das Telefon nicht bootet/bootloopt |
| `--no-reboot`   | danach im Fastboot bleiben |
| `-s SERIAL`     | bestimmtes Gerät bei mehreren angeschlossenen |
| `-y`            | ohne Rückfrage |

Erster Start dauert 1–2 Minuten. Anmelden mit der PIN (Standard `147147`), danach sofort
`passwd` ausführen. Per USB ist das Telefon zusätzlich als Netzwerkgerät erreichbar
(`ssh user@172.16.42.1`, sofern SSH installiert/aktiviert ist).

Zurück zu Android: Xiaomi-Fastboot-ROM mit MiFlash bzw. `flash_all.sh` flashen.

## 5. Build per Klick mit GitHub Actions

### Einmalig einrichten

```bash
cd ~/nura
git init -b main
git add .
git commit -m "Nura build kit for POCO X3 Pro (vayu)"
gh repo create nura-vayu --public --source . --push   # oder Repo im Browser anlegen + git push
```

Optional unter **Settings → Secrets and variables → Actions** ein Secret `NURA_PASSWORD` anlegen.
Dann wird dieses Passwort statt des Eingabefeldes verwendet und taucht nicht in den Run-Parametern auf.

### Neuen Build starten

1. Im Repo auf **Actions → „Build Nura image (POCO X3 Pro / vayu)“** gehen
2. **Run workflow** klicken
3. Optionen wählen und starten:

| Eingabe          | Bedeutung |
|------------------|-----------|
| `panel`          | `both` (Standard, baut tianma **und** huaxing parallel), `tianma`, `huaxing` |
| `ui`             | Oberfläche |
| `channel`        | `edge` oder Release |
| `ui_extras`      | UI-Zusatzpakete |
| `extra_packages` | zusätzliche Pakete |
| `filesystem`     | Dateisystem |
| `password`       | Start-PIN (wird ignoriert, wenn das Secret `NURA_PASSWORD` existiert) |
| `runner`         | `ubuntu-24.04-arm` = nativ aarch64, ca. 30–60 min · `ubuntu-24.04` = x86 mit QEMU-Emulation, deutlich langsamer |
| `release`        | Ergebnis als GitHub-Release veröffentlichen |

Alternativ per CLI:

```bash
gh workflow run build.yml -f panel=tianma -f ui=phosh -f channel=edge
gh run watch
```

### Ergebnis

- Jeder Build-Job lädt `nura-xiaomi-vayu-<panel>-<ui>-<channel>-<datum>.tar.zst` (+ `.sha256`)
  als **Artefakt** hoch (14 Tage aufbewahrt, Download im Run unter „Artifacts“).
- Mit `release: true` entsteht zusätzlich ein **Release** (Tag `nura-vayu-<ui>-<channel>-<datum>-r<run>`,
  bei `edge` als Pre-Release) mit allen Archiven.
- Schlägt ein Build fehl, wird `pmbootstrap-log-<panel>` mit dem vollständigen pmbootstrap-Log hochgeladen.

Ein Artefakt-ZIP kann `flash.sh` direkt verarbeiten: `./flash.sh nura-xiaomi-vayu-....zip`.

Automatische wöchentliche Builds: im Workflow den auskommentierten `schedule:`-Block aktivieren.

> Hinweise: Die arm64-Runner (`ubuntu-24.04-arm`) sind für öffentliche Repos kostenlos; bei privaten
> Repos ggf. `ubuntu-24.04` wählen. Release-Dateien dürfen max. 2 GB groß sein – mit Phosh/zstd liegt
> das Archiv normalerweise deutlich darunter.

## 6. Fehlersuche

| Problem | Lösung |
|---------|--------|
| Schwarzer Bildschirm, Telefon läuft aber (warm, USB-Netzwerk erscheint) | falsches Panel → mit dem anderen `--panel` bauen und `./flash.sh --boot-only` |
| Bootloop / zurück in Fastboot | `./flash.sh --boot-only --erase-dtbo` |
| `No fastboot device found` | anderes Kabel/USB-2-Port, udev-Regeln (`android-udev-rules`) oder testweise `sudo fastboot devices` |
| `product` ist nicht `vayu` | falsches Gerät – Script bricht absichtlich ab |
| Build: `device-xiaomi-vayu not found` | Gerät fehlt im gewählten Channel → `edge` verwenden |
| Build bricht in pmbootstrap ab | `build/work/log.txt` (lokal) bzw. Artefakt `pmbootstrap-log-*` ansehen; `./build.sh --clean` |
| Paket aus `--extra` nicht gefunden | Paketnamen auf [pkgs.nura.eco](https://pkgs.nura.eco) / [pkgs.alpinelinux.org](https://pkgs.alpinelinux.org) prüfen |

## Wie es funktioniert

`build.sh` ersetzt das interaktive `pmbootstrap init` durch eine generierte Config:

1. pmbootstrap (neuester Release-Tag) nach `build/pmbootstrap` klonen
2. pmaports für den Channel (`edge` → Branch `main`, `v26.06` → `v26.06`) nach `build/pmaports` holen
3. `build/pmbootstrap_v3.cfg` schreiben: `device = xiaomi-vayu`, `kernel = <panel>`, UI, Benutzer usw.
4. `pmbootstrap install --sparse` baut Rootfs und `boot.img` (fastboot-Methode laut `deviceinfo`)
5. `pmbootstrap export` → `boot.img` + `xiaomi-vayu.img` (als `userdata.img`) ins Flash-Kit kopieren,
   Checksummen + `build-info.txt` erzeugen, mit zstd packen

Das entspricht dem offiziellen Weg `pmbootstrap init` → `pmbootstrap install` →
`pmbootstrap flasher flash_rootfs` / `flash_kernel`, nur reproduzierbar und ohne Rückfragen.
