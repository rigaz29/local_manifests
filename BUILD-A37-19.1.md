# Building LineageOS 19.1 (Android 12L) — OPPO A37 (A37f)

SoC: Qualcomm MSM8916/MSM8939 (Snapdragon 410/615), Cortex-A53
Build type: **32-bit userspace (armeabi-v7a) + 64-bit kernel (arm64)**

> Recipe adapted from **retiredtab**'s proven msm8916 19.1 build recipe
> (`retiredtab/LineageOS-build-manifests/19.1`). retiredtab maintains Samsung
> Galaxy Tab msm8916/8929/8939 devices — same chipset family as the A37 — so the
> **platform-level and framework-level** steps below are portable to the A37.
> Device-specific parts (blobs, kernel drivers, panel, partitions) are NOT.

---

## 0. Prerequisites
- ~250 GB free disk, 16 GB+ RAM (swap helps), Linux build host
- `repo`, `git`, JDK, and the usual AOSP build deps installed

## 1. Init source + local manifest
```bash
mkdir -p ~/android/lineage-19.1 && cd ~/android/lineage-19.1
repo init -u https://github.com/LineageOS/android.git -b lineage-19.1

mkdir -p .repo/local_manifests
curl -o .repo/local_manifests/A37.xml \
  https://raw.githubusercontent.com/rigaz29/local_manifests/main/A37.xml

repo sync -c -j$(nproc)
```

This pulls (from `A37.xml`):
| Path | Source |
|------|--------|
| `device/oppo/A37` | rigaz29/rb_device_oppo_A37 @ lineage-19.1 |
| `device/cyanogen/msm8916-common` | rigaz29/android_device_cyanogen_msm8916-common @ lineage-19.1 |
| `kernel/oppo/msm8939` | rigaz29/kernel_oppo_msm8939 @ 0.0 |
| `vendor/oppo` | rigaz29/proprietary_vendor_oppo_A37 @ lineage-19.1 |
| `hardware/qcom-caf/msm8916/{audio,display,media}` | LineageOS @ lineage-19.0-caf-msm8916 |

`stlport` + `sony/timekeep` are pulled by roomservice from the device tree's
(already-fixed) `lineage.dependencies` during `breakfast`.

## 2. breakfast
```bash
source build/envsetup.sh
breakfast A37
```

## 3. Legacy repopick patches  (device-agnostic — needed by ALL msm8916 legacy on 19.1)
```bash
repopick -P art -f 318097
repopick -P external/perfetto -f 287706
repopick -f 321934
repopick -f 326385
repopick -P system/bpf -f 320591
repopick -P system/netd -f 320592
# camera feature extensions
repopick -f 318817
# vendor/lineage soong: camera_in_mediaserver_defaults
repopick -f 320546
```
> Re-run these after every full `repo sync`.

## 4. Restore legacy Camera HAL 1.0 + Audio HAL 2.0  (REQUIRED for A37)
The A37 device tree uses the old camera path (`camera/CameraWrapper.cpp`,
`libshims/camera_shim.c`) and legacy audio — both removed upstream in 19.1.
retiredtab provides the full patch set:

```bash
# Grab retiredtab's framework patch bundle
curl -Lo /tmp/hal-patches-191.zip \
  "https://raw.githubusercontent.com/retiredtab/LineageOS-build-manifests/main/19.1/audio-camera-hal-patches-for-191.zip"
unzip /tmp/hal-patches-191.zip -d /tmp/hal-patches-191

# Apply frameworks/av patches (0001..0022 — camera HALv1 + audio HALv2)
cd frameworks/av
for p in /tmp/hal-patches-191/frameworksav/*.patch; do patch -p1 < "$p"; done
cd ../..

# Apply frameworks/base patches (0001..0005 — camera HALv1, sig spoofing, etc.)
cd frameworks/base
for p in /tmp/hal-patches-191/frameworksbase/*.patch; do patch -p1 < "$p"; done
cd ../..
```
> Verify the folder names inside the zip after unzip; adjust the loop paths if
> retiredtab flattened them. The exact ordered list is in
> `19.1/191-msm8916-build-instructions.txt`.

## 5. Revert libbfqio removal  (msm8916 display HAL needs it)
```bash
cd vendor/lineage
git revert --no-edit 8f67d055b36d992f2f09aa6f733aa06ee3d5b917
cd ../..
```
Fixes: `hwcomposer.msm8916 ... missing libbfqio`.

## 6. Build
```bash
brunch A37 2>&1 | tee build-A37.log
```

---

## What we already fixed in the forks (don't redo)
- `device/oppo/A37`: repaired malformed `lineage.dependencies` JSON (+ pinned dep branches).
- `device/cyanogen/msm8916-common`: removed the dead `device/qcom/sepolicy-legacy`
  include (retiredtab pattern) — uses in-tree `sepolicy/` instead.
- `A37.xml`: consistent all-19.1 manifest replacing the broken `manifest_A37`.

## Watch-items for the first build log
1. **sepolicy compile errors** (missing base types) → supplement from
   `retiredtab/msm8916_sepolicy_vendor` @ lineage-19.1 (45 `.te` files).
2. **kernel** (`kernel/oppo/msm8939`, defconfig `lineageos_a37f_defconfig`, arch arm64):
   3.10 kernel on 12L may need small backports — reference
   `retiredtab/android_kernel_samsung_msm8916` (msm8916/8939, builds 19.1+).
3. **`F_DUPFD_CLOEXEC` undeclared** → patch at
   `19.1/use of undeclared identifier 'F_DUPFD_CLOEXEC'.patch` in retiredtab's repo.
4. After it boots: flip SELinux `permissive` → `enforcing` and clear denials
   (`adb shell dmesg | grep avc`).

## Portable vs NOT (from retiredtab → A37)
| Portable (same chipset/era) | NOT portable (device-specific) |
|---|---|
| sepolicy approach, framework HAL patches | vendor blobs (Samsung ≠ OPPO) |
| repopick list, libbfqio revert | kernel device drivers (panel/touch/sensor) |
| build sequence / gotchas | device tree overlays, partitions, fingerprint |
