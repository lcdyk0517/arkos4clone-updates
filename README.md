# arkos4clone OTA Update System

An OTA update pipeline for arkos4clone, modeled after the dArkOS update scheme. The core is **one accumulating update script** in this repository: every release appends a new dated block to the end of that script. Update packages are **split zip volumes** — the full zip is cut into 45MB chunks (`.zip.001 / .002 / ...`), each below GitHub's 50MB per-file limit, so packages larger than 50MB can still be shipped. On the device, blocks are applied one by one and tracked by marker files at `/home/ark/.update/.<date>`; already-applied blocks are skipped.

All releases from **20260930** onward are delivered through this system.

---

## Updating your device (user guide)

### A. You are on 20260930 or 20261004 — one-time bootstrap (online)

These two versions predate the ES menu entry, so the first update is bootstrapped manually:

1. Download [`device/Update.sh`](device/Update.sh) from this repository.
2. Copy it into the `/roms/ports` folder on your SD card.
3. Launch it from the **Ports** section in EmulationStation.
4. It downloads the latest update over the network, applies it and reboots.

Once you are on **20261005 or later**, all future updates are done from the ES menu (option B) — you can delete the script from `/roms/ports` afterwards.

### B. You are on 20261005 or later — online update from the ES menu

**EmulationStation menu → arkos4clone settings → Update.**

The device downloads everything it needs over the network and reboots when finished. A device several releases behind catches up with all missing releases in a single run.

### C. Offline update (device has no internet)

1. From this repository, download:
   - `ArkOS4CloneUpdate.sh` (in `update_files/`), and
   - the volume folder of the release you want: `update_files/<date>/ArkOS4CloneUpdate-<date>.zip.00x`
2. Copy them to the SD card:
   - `ArkOS4CloneUpdate.sh` → `/roms/update/`
   - the volumes → `/roms/update/<date>/`
3. Run the update:
   - on 20260930 / 20261004: run `Update.sh` from `/roms/ports` as in section A;
   - on 20261005 or later: **EmulationStation menu → arkos4clone settings → Local update**.

On success the script and every applied date folder are removed from `/roms/update/` automatically. If something fails you get exactly one error box; the log stays at `/home/ark/esupdate.log` for inspection.
