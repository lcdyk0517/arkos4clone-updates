# arkos4clone OTA Update System

An OTA update pipeline for arkos4clone, modeled after the dArkOS update scheme. The core is **one accumulating update script** in the repository: every release appends a new dated block to the end of that script. Update packages are **split zip volumes** — the full zip is cut into 45MB chunks (`.zip.001 / .002 / ...`), each below GitHub's 50MB per-file limit, so packages larger than 50MB can still be shipped. On the device, blocks are applied one by one and tracked by marker files at `/home/ark/.update/.<date>`; already-applied blocks are skipped.

## How it works

```
Device-side Update.sh (device/Update.sh)
  ├─ Offline mode: if /roms/update/ArkOS4CloneUpdate.sh (or /roms2/update) exists -> run it directly
  ├─ Otherwise download update_files/ArkOS4CloneUpdate.sh from the repo to /home/ark and run it
  └─ On success (exit 187): offline mode deletes the used script plus every applied
     date folder; online mode deletes the downloaded script
        │
ArkOS4CloneUpdate.sh (the accumulating script, lives in update_files/)
  ├─ If the marker /home/ark/.update/.<UPDATE_DATE> already exists -> "No more updates", exit 187
  ├─ console_detect -V decides the system type and the sync order:
  │     dArkOS4Clone -> sync the dArkOS folder only
  │     ArkOS4Clone  -> sync the dArkOS folder first, then the ArkOS folder
  ├─ Requires unzip; aborts with a message if missing
  └─ For each dated block (oldest first, newest last), if its marker is missing:
          1. Probe /roms/update/<date> (then /roms2/update/<date>) for the first volume;
             otherwise target /roms/update/<date> (created if missing)
          2. Check every volume by VOL_COUNT and wget the missing ones
             (served from update_files/<date>/ on the repo)
          3. cat the volumes back into one zip, verify it with unzip -t
          4. For each folder in SYNC_FOLDERS: unzip into /home/ark/.update_tmp,
             chown ark:ark + chmod 777, then cp -af to /
          5. sync
          6. touch /home/ark/.update/.<block date>
        Any failure: one error message box, exit 1, no marker written (the block is
        retried on the next update), no reboot
  └─ When all blocks are done: write .VERSION, update the boot splash title,
     msgbox, sudo reboot, exit 187
```

A device several releases behind catches up with every missing block in a single run. Volumes are kept in `/roms/update/<date>/`, so the same block never downloads twice.

## Repository layout

| Path | Committed | Purpose |
|---|---|---|
| `pack_update.sh` | yes | Packager: copies the update script from `update_files/` and appends a new dated block |
| `update_files/` | yes | `ArkOS4CloneUpdate.sh` plus one folder per date holding the volumes (`update_files/<date>/ArkOS4CloneUpdate-<date>.zip.00x`); the device downloads from here |
| `device/Update.sh` | deploy to device | Device-side update entry point (with offline mode) |
| `payload/` | optional | Update content: `ArkOS/` and `dArkOS/` folders, paths relative to the device root |
| `dist/` | **no** | Packer output. The update script sits at `dist/` root — it belongs to no single date, it drives all packages — and the volumes go to `dist/<date>/`. After testing: move the script into `update_files/`, the volumes into `update_files/<date>/` |
| `Update.sh` (repo root) | reference only | The stock dArkOS entry script; do not deploy |

## Packaging

```bash
./pack_update.sh [payload dir] [repo dir]
# Defaults: ./payload and . (this workspace); the script is read from update_files/
# Env var PACK_DATE=YYYYMMDD overrides the date (for back-filling old releases); defaults to today
# Requires zip/unzip/split (apt install zip unzip; split ships with coreutils)
```

Each run:

1. Validates the payload, the structure of `update_files/ArkOS4CloneUpdate.sh`, that no block with this date exists yet, and that dist holds no newer un-pushed script;
2. Zips the payload (top level must contain only `ArkOS` and `dArkOS`), then splits it at 45MB into `ArkOS4CloneUpdate-<date>.zip.001 .002 ...` with every chunk verified below 50MB; volumes land in `dist/<date>/`;
3. Copies `ArkOS4CloneUpdate.sh` from `update_files/`, strips the old footer (everything from the `# ==== ARKOS4CLONE_PACKER_FOOTER` marker to EOF), appends the new dated block (the actual volume count is written into `VOL_COUNT`), regenerates the footer, and rewrites the header `UPDATE_DATE` to the pack date;
4. Runs `bash -n` on the generated script.

**Release loop**: pack → test (put the script at `/roms/update` and the volumes at `/roms/update/<date>/` for an offline test, or just run OTA) → move the script into `update_files/` and the volumes into `update_files/<date>/` → `git add update_files && git commit && git push` (`dist/` is never committed) → repeat in a few days.

Two guard rails: packing is refused when the dist script is newer than `update_files/` (this protects an un-pushed block from being lost), and refused when `update_files/` already contains a block with the same date.

Old blocks and volumes stay in the repository forever; devices catch up block by block via the markers, so a device on any old version can always climb to the latest release.

## Device setup

- Deploy `device/Update.sh` where the system's "Update" entry invokes it (where the stock dArkOS `Update.sh` lives) and `chmod 777` it. Compared to the stock script: the update source points at `lcdyk0517/arkos4clone-updates`, the stock `wget ... || rm ... | tee` bug (which made `$?` always 0, leaving the download-failure branch dead) is fixed, and offline mode is added.
- **The ROM image must include unzip.** Packages are split zips; joining them only needs the system `cat`, so there is no other dependency. Without unzip the script aborts with a message box.
- **Offline updates**: put `ArkOS4CloneUpdate.sh` at the root of `/roms/update/` (or `/roms2/update/`) and the volumes of a given date into `/roms/update/<date>/`, then run the normal update — no internet needed. On success the script and **all applied date folders** are removed automatically; the same cleanup runs when the device turns out to be already up to date.
- For OTA, volumes are downloaded on demand into `/roms/update/<date>/` and kept there (the same block never downloads twice).

## Conventions and notes

- **Markers**: each applied block touches the hidden file `/home/ark/.update/.<date>`. If the marker for the header `UPDATE_DATE` exists, the device is considered up to date.
- **Boot splash title**: after an update the title is rewritten in the same format the image build script uses: `title=<system> (<date>)(<MODDER>)`. Change `MODDER` in the header of `update_files/ArkOS4CloneUpdate.sh` (currently `kk&lcdyk`). Dates are `YYYYMMDD` everywhere in this system.
- **Do not hand-edit the footer**: everything after `# ==== ARKOS4CLONE_PACKER_FOOTER` is rewritten on every pack. The dated-block region may be tuned by hand; the packer keeps existing blocks byte-for-byte.
- **Sync is merge-only** (same as dArkOS's `unzip -o -d /`): files are added or overwritten, never deleted. To remove files, ship a cleanup script in the payload or `rm` explicitly inside a block. On ArkOS4Clone devices the ArkOS folder is applied last, so it wins over same-path files in dArkOS.
- **Security model matches the stock one**: downloads use `--no-check-certificate` and nothing is signature-verified. To harden, write the zip's sha256 into the dated block at pack time and verify it on the device before applying.
- `console_detect -V` must print `ArkOS4Clone` or `dArkOS4Clone`; anything else aborts the update with a message box.
- No LICENSE file is needed in the repo — the device entry downloads `update_files/ArkOS4CloneUpdate.sh` itself, which doubles as the connectivity probe.

## Git

The `origin` remote is already configured:

```
git remote -v
# origin  git@github.com:lcdyk0517/arkos4clone-updates.git

git add update_files device pack_update.sh payload .gitignore README.md
git commit -m "arkos4clone OTA update system"
git push -u origin master
```
