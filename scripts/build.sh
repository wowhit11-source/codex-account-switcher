#!/bin/zsh
set -euo pipefail

cas_project_root="$(cd "$(dirname "$0")/.." && pwd)"
cas_scratch_path="${CAS_BUILD_DIR:-/private/tmp/codex-account-switcher-build-${UID}}"
cas_module_cache="${CAS_MODULE_CACHE:-/private/tmp/codex-account-switcher-module-cache-${UID}}"
cas_cache_home="${CAS_CACHE_HOME:-/private/tmp/codex-account-switcher-cache-${UID}}"
cas_app_name="Codex Account Switcher.app"
cas_app_path="$cas_project_root/dist/$cas_app_name"
cas_staging_path="$cas_project_root/dist/.Codex Account Switcher.app.building"

mkdir -p "$cas_project_root/dist" "$cas_scratch_path" "$cas_module_cache" "$cas_cache_home"

env \
  CLANG_MODULE_CACHE_PATH="$cas_module_cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$cas_module_cache" \
  XDG_CACHE_HOME="$cas_cache_home" \
  swift build \
    --disable-sandbox \
    --scratch-path "$cas_scratch_path" \
    --configuration release \
    --product CodexAccountSwitcher

cas_binary_directory="$(
  env \
    CLANG_MODULE_CACHE_PATH="$cas_module_cache" \
    SWIFTPM_MODULECACHE_OVERRIDE="$cas_module_cache" \
    XDG_CACHE_HOME="$cas_cache_home" \
    swift build \
      --disable-sandbox \
      --scratch-path "$cas_scratch_path" \
      --configuration release \
      --show-bin-path
)"
cas_binary="$cas_binary_directory/CodexAccountSwitcher"

test -x "$cas_binary"
test "$(basename "$cas_staging_path")" = ".Codex Account Switcher.app.building"
test "$(basename "$cas_app_path")" = "$cas_app_name"

if [ -e "$cas_staging_path" ]; then
  /bin/rm -rf "$cas_staging_path"
fi
mkdir -p "$cas_staging_path/Contents/MacOS" "$cas_staging_path/Contents/Resources/Documentation"
/usr/bin/ditto "$cas_binary" "$cas_staging_path/Contents/MacOS/CodexAccountSwitcher"
/usr/bin/ditto "$cas_project_root/Resources/Info.plist" "$cas_staging_path/Contents/Info.plist"
/usr/bin/ditto "$cas_project_root/docs" "$cas_staging_path/Contents/Resources/Documentation"
/usr/bin/ditto "$cas_project_root/README_KO.md" "$cas_staging_path/Contents/Resources/Documentation/README_KO.md"
/usr/bin/ditto "$cas_project_root/SECURITY.md" "$cas_staging_path/Contents/Resources/Documentation/SECURITY.md"
/bin/chmod 755 "$cas_staging_path/Contents/MacOS/CodexAccountSwitcher"
/usr/bin/codesign --force --deep --sign - "$cas_staging_path"
/usr/bin/plutil -lint "$cas_staging_path/Contents/Info.plist"
/usr/bin/codesign --verify --deep --strict "$cas_staging_path"

if [ -e "$cas_app_path" ]; then
  /bin/rm -rf "$cas_app_path"
fi
/bin/mv "$cas_staging_path" "$cas_app_path"

printf '%s\n' "$cas_app_path"
