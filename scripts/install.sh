#!/bin/zsh
set -euo pipefail

cas_project_root="$(cd "$(dirname "$0")/.." && pwd)"
cas_source="$cas_project_root/dist/Codex Account Switcher.app"
cas_install_root="$HOME/Applications"
cas_destination="$cas_install_root/Codex Account Switcher.app"
cas_staging="$cas_install_root/.Codex Account Switcher.app.installing"

if [ ! -d "$cas_source" ]; then
  "$cas_project_root/scripts/build.sh"
fi

mkdir -p "$cas_install_root"
if [ -e "$cas_staging" ]; then
  /bin/rm -rf "$cas_staging"
fi
/usr/bin/ditto "$cas_source" "$cas_staging"
/usr/bin/codesign --verify --deep --strict "$cas_staging"

if [ -e "$cas_destination" ]; then
  /bin/rm -rf "$cas_destination"
fi
/bin/mv "$cas_staging" "$cas_destination"
printf '%s\n' "$cas_destination"
