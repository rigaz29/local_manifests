#!/usr/bin/env bash
#
# apply-legacy-patches-A37.sh
# Automates the device-agnostic legacy patches needed to build LineageOS 19.1
# for msm8916-legacy devices (OPPO A37), adapted from retiredtab's recipe.
#
# Run from the ROOT of your lineage-19.1 source tree, AFTER:
#   source build/envsetup.sh && breakfast A37
#
set -euo pipefail

RT_BASE="https://raw.githubusercontent.com/retiredtab/LineageOS-build-manifests/main/19.1"

say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

[ -d build/soong ] || { echo "ERROR: run me from the top of the lineage-19.1 tree"; exit 1; }

# ---------------------------------------------------------------------------
say "1/4  repopick legacy changes"
repopick -P art -f 318097
repopick -P external/perfetto -f 287706
repopick -f 321934
repopick -f 326385
repopick -P system/bpf -f 320591
repopick -P system/netd -f 320592
repopick -f 318817                 # system/core Camera feature extensions
repopick -f 320546                 # vendor/lineage camera_in_mediaserver_defaults

# ---------------------------------------------------------------------------
say "2/4  Restore Camera HAL 1.0 + Audio HAL 2.0 (frameworks/av + base)"
TMP="$(mktemp -d)"
curl -Lo "$TMP/hal.zip" "$RT_BASE/audio-camera-hal-patches-for-191.zip"
unzip -q "$TMP/hal.zip" -d "$TMP/hal"

apply_dir() {  # $1 = target git dir, $2 = patch source dir
  local tgt="$1" src="$2"
  [ -d "$src" ] || { echo "  WARN: $src not found in zip — check layout, applying skipped"; return 0; }
  ( cd "$tgt"
    for p in "$src"/*.patch; do
      echo "  patch: $(basename "$p")"
      patch -p1 < "$p"
    done )
}
# retiredtab's zip layout: frameworksav/ and frameworksbase/ (verify if it errors)
apply_dir frameworks/av   "$(find "$TMP/hal" -type d -iname '*av*'   | head -1)"
apply_dir frameworks/base "$(find "$TMP/hal" -type d -iname '*base*' | head -1)"

# ---------------------------------------------------------------------------
say "3/4  Revert libbfqio removal (msm8916 display HAL dependency)"
( cd vendor/lineage
  if git merge-base --is-ancestor 8f67d055b36d992f2f09aa6f733aa06ee3d5b917 HEAD 2>/dev/null; then
    git revert --no-edit 8f67d055b36d992f2f09aa6f733aa06ee3d5b917 || \
      echo "  (already reverted or conflict — resolve manually)"
  else
    echo "  commit not present on this branch — skip (may not be needed)"
  fi )

# ---------------------------------------------------------------------------
say "4/4  Done. Now build:  brunch A37 2>&1 | tee build-A37.log"
echo "If you hit \"F_DUPFD_CLOEXEC undeclared\", fetch:"
echo "  $RT_BASE/use%20of%20undeclared%20identifier%20'F_DUPFD_CLOEXEC'.patch"
rm -rf "$TMP"
