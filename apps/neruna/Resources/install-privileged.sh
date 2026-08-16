#!/bin/bash
set -euo pipefail

SRC="${1:?staging directory required}"
HELPER_SRC="${SRC}/neruna-helper"
PLIST_SRC="${SRC}/plist"
SUDOERS_SRC="${SRC}/sudoers"

if [[ ! -x "${HELPER_SRC}" ]]; then
  echo "neruna-helper is missing in ${SRC}" >&2
  exit 1
fi
if [[ ! -f "${PLIST_SRC}" ]]; then
  echo "LaunchDaemon plist is missing in ${SRC}" >&2
  exit 1
fi
if [[ ! -f "${SUDOERS_SRC}" ]]; then
  echo "sudoers is missing in ${SRC}" >&2
  exit 1
fi

/usr/sbin/visudo -cf "${SUDOERS_SRC}"

/usr/bin/install -d -m 0755 /usr/local/libexec
/usr/bin/install -d -m 0755 /usr/local/var/neruna
/usr/bin/install -m 0755 -o root -g wheel "${HELPER_SRC}" /usr/local/libexec/neruna-helper
/usr/bin/install -m 0644 -o root -g wheel "${PLIST_SRC}" /Library/LaunchDaemons/app.soprog.magonote.neruna.helper.plist
/usr/bin/install -m 0440 -o root -g wheel "${SUDOERS_SRC}" /etc/sudoers.d/neruna

/bin/launchctl bootout system /Library/LaunchDaemons/app.soprog.magonote.neruna.helper.plist 2>/dev/null || true
/bin/launchctl bootstrap system /Library/LaunchDaemons/app.soprog.magonote.neruna.helper.plist
/bin/launchctl enable system/app.soprog.magonote.neruna.helper
/bin/launchctl kickstart -k system/app.soprog.magonote.neruna.helper
