#!/bin/zsh
set -euo pipefail

cas_project_root="$(cd "$(dirname "$0")/.." && pwd)"
cas_installed_binary="$HOME/Applications/Codex Account Switcher.app/Contents/MacOS/CodexAccountSwitcher"
cas_dist_binary="$cas_project_root/dist/Codex Account Switcher.app/Contents/MacOS/CodexAccountSwitcher"

if [ -x "$cas_installed_binary" ]; then
  exec "$cas_installed_binary" --emergency-restore
fi
if [ -x "$cas_dist_binary" ]; then
  exec "$cas_dist_binary" --emergency-restore
fi

printf '%s\n' 'Codex Account Switcher 실행 파일을 찾지 못했습니다.' >&2
exit 1
