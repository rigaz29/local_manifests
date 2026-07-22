#!/usr/bin/env bash
#
# apply-legacy-patches-A37.sh
# Automates the device-agnostic legacy patches needed to build LineageOS 19.1
# for msm8916-legacy devices (OPPO A37), adapted from retiredtab's recipe.
#
# Run from the ROOT of your lineage-19.1 source tree:
#   cd ~/android/lineage
#   bash <(curl -s .../apply-legacy-patches-A37.sh)
#
# The script sources build/envsetup.sh itself, so `repopick` works even when
# launched in a subshell via `bash <(curl ...)`.

RT_BASE="https://raw.githubusercontent.com/retiredtab/LineageOS-build-manifests/main/19.1"
say() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

[ -d build/soong ] || { echo "ERROR: run me from the top of the lineage-19.1 tree (cd ~/android/lineage)"; exit 1; }

# ---------------------------------------------------------------------------
say "0/4  loading build environment (envsetup.sh)"
set +u
# shellcheck disable=SC1091
source build/envsetup.sh >/dev/null 2>&1
set -u
if ! command -v repopick >/dev/null 2>&1; then
  echo "ERROR: 'repopick' still not available after sourcing build/envsetup.sh."
  echo "       Make sure you are in the source root and the tree synced fully."
  exit 1
fi

# repopick wrapper: never abort the whole run if one change is already applied/abandoned
rp() { repopick "$@" || echo "  (repopick $* skipped — already applied / not found; continuing)"; }

# ---------------------------------------------------------------------------
say "1/4  repopick legacy changes"
rp -P art -f 318097
rp -P external/perfetto -f 287706
rp -f 321934
rp -f 326385
rp -P system/bpf -f 320591
rp -P system/netd -f 320592
rp -f 318817                 # system/core Camera feature extensions
rp -f 320546                 # vendor/lineage camera_in_mediaserver_defaults

# ---------------------------------------------------------------------------
say "2/4  Restore Camera HAL 1.0 + Audio HAL 2.0 (frameworks/av + base)"
TMP="$(mktemp -d)"
if curl -fLo "$TMP/hal.zip" "$RT_BASE/audio-camera-hal-patches-for-191.zip" && unzip -q "$TMP/hal.zip" -d "$TMP/hal"; then
  apply_dir() {  # $1 = target git dir, $2 = patch source dir
    local tgt="$1" src="$2"
    [ -n "$src" ] && [ -d "$src" ] || { echo "  WARN: patch dir for $tgt not found in zip — skipped (inspect $TMP/hal)"; return 0; }
    ( cd "$tgt" || return 0
      for p in "$src"/*.patch; do
        [ -f "$p" ] || continue
        echo "  patch: $(basename "$p")"
        patch -p1 --forward < "$p" || echo "    (already applied or rejected — check .rej files)"
      done )
  }
  apply_dir frameworks/av   "$(find "$TMP/hal" -type d -iname '*av*'   | head -1)"
  apply_dir frameworks/base "$(find "$TMP/hal" -type d -iname '*base*' | head -1)"
else
  echo "  WARN: could not download/unzip HAL patch bundle — apply manually later."
fi
rm -rf "$TMP"

# ---------------------------------------------------------------------------
say "3/4  Revert libbfqio removal (msm8916 display HAL dependency)"
if [ -d vendor/lineage ]; then
  ( cd vendor/lineage
    if git merge-base --is-ancestor 8f67d055b36d992f2f09aa6f733aa06ee3d5b917 HEAD 2>/dev/null; then
      git revert --no-edit 8f67d055b36d992f2f09aa6f733aa06ee3d5b917 \
        || echo "  (already reverted or conflict — resolve manually)"
    else
      echo "  commit not present on this branch — skip (may not be needed)"
    fi )
else
  echo "  vendor/lineage not found — skip"
fi

# ---------------------------------------------------------------------------
say "4/4  Done. Now build:  brunch A37 2>&1 | tee build-A37.log"
echo "If you later hit \"F_DUPFD_CLOEXEC undeclared\", fetch:"
echo "  $RT_BASE/use%20of%20undeclared%20identifier%20'F_DUPFD_CLOEXEC'.patch"
