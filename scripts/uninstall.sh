#!/bin/zsh
set -euo pipefail

cas_project_root="$(cd "$(dirname "$0")/.." && pwd)"
cas_installed_app="$HOME/Applications/Codex Account Switcher.app"
cas_dist_app="$cas_project_root/dist/Codex Account Switcher.app"
cas_purge_data="${1:-}"

if [ "$cas_purge_data" = "--purge-data" ]; then
  if [ -x "$cas_installed_app/Contents/MacOS/CodexAccountSwitcher" ]; then
    "$cas_installed_app/Contents/MacOS/CodexAccountSwitcher" --purge-data
  elif [ -x "$cas_dist_app/Contents/MacOS/CodexAccountSwitcher" ]; then
    "$cas_dist_app/Contents/MacOS/CodexAccountSwitcher" --purge-data
  fi
fi

if [ -e "$cas_installed_app" ]; then
  /bin/rm -rf "$cas_installed_app"
fi

printf 'removed: %s\n' "$cas_installed_app"
if [ "$cas_purge_data" != "--purge-data" ]; then
  printf '%s\n' '암호화 프로필은 보존했습니다. 완전 삭제는 --purge-data 옵션을 사용하세요.'
fi
