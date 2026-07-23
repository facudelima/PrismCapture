#!/usr/bin/env bash
# Build PrismCapture.app (Release) and zip it for GitHub Releases.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

VERSION="${1:-1.0.0}"
OUT_DIR="${ROOT}/dist"
ARCHIVE_PATH="${OUT_DIR}/PrismCapture.xcarchive"
APP_NAME="PrismCapture"
ZIP_NAME="${APP_NAME}-${VERSION}-macos.zip"
LOG_FILE="${OUT_DIR}/xcodebuild.log"

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

echo "→ Building Release…"
set +e
xcodebuild \
  -project PrismCapture.xcodeproj \
  -scheme PrismCapture \
  -configuration Release \
  -derivedDataPath "${OUT_DIR}/DerivedData" \
  -archivePath "${ARCHIVE_PATH}" \
  archive \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  >"${LOG_FILE}" 2>&1
BUILD_STATUS=$?
set -e

if [[ ${BUILD_STATUS} -ne 0 ]]; then
  echo "xcodebuild falló (exit ${BUILD_STATUS}). Últimas líneas:" >&2
  tail -n 80 "${LOG_FILE}" >&2
  exit "${BUILD_STATUS}"
fi

# Prefer archive product; fall back to built .app
APP_SRC=""
if [[ -d "${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app" ]]; then
  APP_SRC="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
else
  APP_SRC="$(find "${OUT_DIR}/DerivedData/Build/Products/Release" -maxdepth 1 -name "${APP_NAME}.app" -print -quit || true)"
fi

if [[ -z "${APP_SRC}" || ! -d "${APP_SRC}" ]]; then
  echo "No se encontró ${APP_NAME}.app tras el build." >&2
  exit 1
fi

cp -R "${APP_SRC}" "${OUT_DIR}/${APP_NAME}.app"

# Ad-hoc sign for local distribution (Gatekeeper still may warn without Developer ID + notarization)
codesign --force --deep --sign - "${OUT_DIR}/${APP_NAME}.app" 2>/dev/null || true

cd "${OUT_DIR}"
ditto -c -k --sequesterRsrc --keepParent "${APP_NAME}.app" "${ZIP_NAME}"

echo "✓ Listo: ${OUT_DIR}/${ZIP_NAME}"
ls -lh "${OUT_DIR}/${ZIP_NAME}"
