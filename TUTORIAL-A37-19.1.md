# Tutorial Build LineageOS 19.1 (Android 12L) — OPPO A37 (A37f)

Panduan lengkap dari mesin kosong sampai ROM ter-flash. Semua perbaikan yang sudah
dikerjakan (device tree, sepolicy, vendor, kernel, **binder Android-12**) sudah
terangkum di manifest — tinggal ikuti langkahnya.

| | |
|---|---|
| **SoC** | Qualcomm MSM8916 (Snapdragon 410), Cortex-A53, Adreno 306 |
| **Tipe build** | 32-bit userspace (`armeabi-v7a`) + kernel arm64 |
| **Fork** | github.com/rigaz29 |
| **Kebutuhan** | Disk 250 GB SSD · RAM 16 GB (+swap) · Ubuntu 20.04/22.04 · ~4–8 jam |

> Versi visual tutorial ini juga ada sebagai Artifact (tema terminal, tombol copy).

---

## Step 1 — Siapkan build environment
Sekali saja per mesin. Install paket build AOSP + tool `repo`.

```bash
# dependency build (Ubuntu)
sudo apt update && sudo apt install -y bc bison build-essential ccache \
  curl flex g++-multilib gcc-multilib git git-lfs gnupg gperf imagemagick \
  lib32readline-dev lib32z1-dev libelf-dev liblz4-tool libsdl1.2-dev libssl-dev \
  libxml2 libxml2-utils lzop pngcrush rsync schedtool squashfs-tools xsltproc \
  zip zlib1g-dev openjdk-11-jdk python3 python-is-python3

# tool "repo"
mkdir -p ~/bin && curl https://storage.googleapis.com/git-repo-downloads/repo > ~/bin/repo
chmod a+x ~/bin/repo && export PATH=~/bin:$PATH

# identitas git
git config --global user.name  "rigaz29"
git config --global user.email "ryanbagas27@gmail.com"
```

---

## Step 2 — Ambil source + local manifest
Init LineageOS 19.1, lalu tambahkan manifest A37 kita yang sudah konsisten (device +
common + kernel + vendor + qcom-caf, semua di revisi 19.1).

```bash
mkdir -p ~/android/lineage && cd ~/android/lineage
repo init -u https://github.com/LineageOS/android.git -b lineage-19.1 --git-lfs

# manifest kita
mkdir -p .repo/local_manifests
curl -o .repo/local_manifests/A37.xml \
  https://raw.githubusercontent.com/rigaz29/local_manifests/main/A37.xml

repo sync -c -j$(nproc) --force-sync --no-clone-bundle --no-tags
```

> ℹ️ `stlport` & `sony/timekeep` ditarik otomatis oleh roomservice saat `breakfast`
> (lewat `lineage.dependencies` yang sudah diperbaiki).

---

## Step 3 — Siapkan device
```bash
source build/envsetup.sh
breakfast A37
```

---

## Step 4 — Patch legacy (WAJIB untuk msm8916)
msm8916 legacy butuh **Camera HAL 1.0 + Audio HAL 2.0** (dibuang di AOSP 12) plus
beberapa revert. Script kita mengotomasi resep retiredtab.

```bash
# jalankan dari root source tree (setelah breakfast)
bash <(curl -s https://raw.githubusercontent.com/rigaz29/local_manifests/main/apply-legacy-patches-A37.sh)
```

Yang dijalankan script:
- **repopick** — art / perfetto / bpf / netd / camera (legacy support)
- **restore Camera HALv1 + Audio HALv2** — patch `frameworks/av` (22) + `frameworks/base` (5)
- **revert libbfqio** — dependency display HAL msm8916

> Ulangi step ini **setiap** habis `repo sync` penuh.

---

## Step 5 — Build ROM
Nyalakan ccache biar build ke-2 jauh lebih cepat.

```bash
export USE_CCACHE=1 CCACHE_EXEC=/usr/bin/ccache
ccache -M 50G

brunch A37 2>&1 | tee build-A37.log
```

Hasil (kalau sukses):
```
out/target/product/A37/lineage-19.1-<tanggal>-UNOFFICIAL-A37.zip
```

> ⚠️ **Build pertama kemungkinan berhenti di error — itu normal** untuk port unofficial.
> Simpan `build-A37.log` dan cek tabel troubleshooting di bawah.

---

## Step 6 — Flash ke device
Butuh recovery (LineageOS Recovery / TWRP) sudah terpasang di A37.

```bash
# 1. boot device ke Recovery
# 2. Wipe -> Format data / factory reset (WAJIB dari stock atau versi lain)
# 3. Apply update -> ADB sideload, lalu di PC:
adb sideload out/target/product/A37/lineage-19.1-*-A37.zip

# 4. (opsional) sideload paket GApps untuk 12.1 / arm / pico
# 5. Reboot system — boot pertama bisa 5–10 menit
```

---

## Troubleshooting (sudah diantisipasi)

| Gejala | Penyebab | Solusi | Status |
|--------|----------|--------|--------|
| Build error di `frameworks/av` (camera/audio) | Patch HAL legacy belum diterapkan | Ulangi **Step 4** setelah tiap `repo sync` penuh | umum |
| Error `sepolicy` / neverallow / missing type | Base policy legacy | Suplemen dari `retiredtab/msm8916_sepolicy_vendor@19.1` (45 file `.te`) | mungkin |
| Bootloop, stuck di logo | servicemanager / binder | Binder Android-12 **sudah di-port** (commit `b8f075d`). Kalau tetap, cek `last_kmsg` | ✅ difix |
| Kamera force close / preview hitam | Camera HALv1 / blob sensor | Step 4 (HALv1). Blob sensor hi545/imx179/ov5648 sudah ada | mungkin |
| Bluetooth tidak nyala | Blob BT HAL absen di vendor | Tarik `bluetooth@1.0-service-qti` dari stock A37 via `extract-files.sh` | runtime |
| `hwcomposer ... missing libbfqio` | libbfqio dihapus upstream | Revert libbfqio (sudah di dalam script Step 4) | ✅ difix |

> ⚠️ **JANGAN jalankan `./setup-makefiles.sh`** di vendor tanpa re-extract blob dulu.
> Makefile vendor sekarang konsisten dengan 282 blob yang ada; regenerasi dari
> `proprietary-files.txt` (481 entri) akan merujuk ~199 blob absen → build error.

---

## Referensi: repo & perbaikan yang sudah masuk

| Repo (di `rigaz29`) | Path build | Perbaikan |
|---------------------|-----------|-----------|
| `rb_device_oppo_A37` | `device/oppo/A37` | Fix `lineage.dependencies` JSON + baris `proprietary-files.txt` 302 |
| `android_device_cyanogen_msm8916-common` | `device/cyanogen/msm8916-common` | Buang include `sepolicy-legacy` yang hilang (pola retiredtab) |
| `kernel_oppo_msm8939` | `kernel/oppo/msm8939` | Port **binder Android-12** (BINDER_FREEZE, SECURITY_CTX); defconfig tervalidasi |
| `proprietary_vendor_oppo_A37` | `vendor/oppo` | Diaudit: makefile konsisten, 32-bit clean, 0 build-breaker |
| `local_manifests` | `.repo/local_manifests` | `A37.xml` + `apply-legacy-patches-A37.sh` |

Basis resep: **LineageOS** + **retiredtab** (maintainer msm8916 19.1 yang terbukti jalan).
