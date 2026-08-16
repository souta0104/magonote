#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEAM_ID="${DEVELOPMENT_TEAM:-FSC6UXXNH2}"
DERIVED="${ROOT}/.build"
APP_DEST="/Applications/Neruna.app"

cd "${ROOT}"
xcodegen generate

xcodebuild \
  -project Neruna.xcodeproj \
  -scheme Neruna \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath "${DERIVED}" \
  DEVELOPMENT_TEAM="${TEAM_ID}" \
  CODE_SIGN_STYLE=Automatic \
  build

APP_SRC="${DERIVED}/Build/Products/Release/Neruna.app"

if [[ ! -d "${APP_SRC}" ]]; then
  echo "Release app was not built at ${APP_SRC}" >&2
  exit 1
fi

rm -rf "${APP_DEST}"
/usr/bin/ditto "${APP_SRC}" "${APP_DEST}"
open "${APP_DEST}"

echo "Installed ${APP_DEST}"
echo "初回起動時に、蓋閉じスリープを止める helper の導入で管理者パスワードを求められる。"
