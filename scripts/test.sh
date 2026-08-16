#!/bin/zsh
set -euo pipefail

cas_project_root="$(cd "$(dirname "$0")/.." && pwd)"
cas_scratch_path="${CAS_BUILD_DIR:-/private/tmp/codex-account-switcher-build-${UID}}"
cas_module_cache="${CAS_MODULE_CACHE:-/private/tmp/codex-account-switcher-module-cache-${UID}}"
cas_cache_home="${CAS_CACHE_HOME:-/private/tmp/codex-account-switcher-cache-${UID}}"

cd "$cas_project_root"
env \
  CLANG_MODULE_CACHE_PATH="$cas_module_cache" \
  SWIFTPM_MODULECACHE_OVERRIDE="$cas_module_cache" \
  XDG_CACHE_HOME="$cas_cache_home" \
  swift test \
    --disable-sandbox \
    --scratch-path "$cas_scratch_path"
