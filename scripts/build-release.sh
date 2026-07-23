#!/usr/bin/env bash
# Build PrismCapture.app (Release) and zip it for GitHub Releases.
# Re-signs with Apple Development when available so TCC (Screen Recording) survives updates.
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

SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ -z "${SIGN_IDENTITY}" || "${SIGN_IDENTITY}" == "-" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
    | head -1 || true)"
fi
if [[ -z "${SIGN_IDENTITY}" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
    | head -1 || true)"
fi

rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"

echo "→ Building Release…"
# Archive unsigned/ad-hoc first (Xcode archive + Apple Development cert pairing is flaky for macOS).
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

if [[ -n "${SIGN_IDENTITY}" ]]; then
  echo "→ Signing with: ${SIGN_IDENTITY}"
  codesign --force --deep --options runtime --sign "${SIGN_IDENTITY}" "${OUT_DIR}/${APP_NAME}.app"
else
  echo "→ No Development / Developer ID cert — leaving ad-hoc (TCC may reset on updates)"
  codesign --force --deep --sign - "${OUT_DIR}/${APP_NAME}.app" 2>/dev/null || true
fi

codesign -dv --verbose=2 "${OUT_DIR}/${APP_NAME}.app" 2>&1 | grep -E '^(Authority|TeamIdentifier|Signature|Identifier)=' || true

cd "${OUT_DIR}"
ditto -c -k --sequesterRsrc --keepParent "${APP_NAME}.app" "${ZIP_NAME}"

echo "✓ Listo: ${OUT_DIR}/${ZIP_NAME}"
ls -lh "${OUT_DIR}/${ZIP_NAME}"
