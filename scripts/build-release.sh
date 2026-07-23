#!/usr/bin/env bash
# Build PrismCapture.app (Release) and zip it for GitHub Releases.
# Signs with a Team-ID designated requirement so Screen Recording TCC survives updates.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

VERSION="${1:-1.0.0}"
OUT_DIR="${ROOT}/dist"
ARCHIVE_PATH="${OUT_DIR}/PrismCapture.xcarchive"
APP_NAME="PrismCapture"
BUNDLE_ID="com.prismcapture.app"
TEAM_ID="AWYV6ST973"
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

echo "Building Release..."
set +e
BUILD_STATUS=1
xcodebuild \
  -project PrismCapture.xcodeproj \
  -scheme PrismCapture \
  -configuration Release \
  -derivedDataPath "${OUT_DIR}/DerivedData" \
  -archivePath "${ARCHIVE_PATH}" \
  archive \
  CODE_SIGN_IDENTITY='-' \
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  >"${LOG_FILE}" 2>&1
BUILD_STATUS=$?
set -e

if [[ "${BUILD_STATUS}" -ne 0 ]]; then
  echo "xcodebuild failed (exit ${BUILD_STATUS}). Last lines:" >&2
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
  echo "PrismCapture.app not found after build." >&2
  exit 1
fi

cp -R "${APP_SRC}" "${OUT_DIR}/${APP_NAME}.app"
APP_OUT="${OUT_DIR}/${APP_NAME}.app"

# Team-ID designated requirement (not CN-pinned) so TCC can survive updates.
REQ='designated => identifier "'"${BUNDLE_ID}"'" and anchor apple generic and certificate leaf[subject.OU] = "'"${TEAM_ID}"'"'

if [[ -n "${SIGN_IDENTITY}" ]]; then
  echo "Signing with: ${SIGN_IDENTITY}"
  echo "Requirement: Team ${TEAM_ID}"
  codesign --force --deep --options runtime \
    --sign "${SIGN_IDENTITY}" \
    --identifier "${BUNDLE_ID}" \
    -r="${REQ}" \
    "${APP_OUT}"
else
  echo "No Development / Developer ID cert — ad-hoc (TCC will reset on each update)" >&2
  codesign --force --deep --sign - "${APP_OUT}" 2>/dev/null || true
fi

echo "Signature:"
codesign -dv --verbose=2 "${APP_OUT}" 2>&1 | grep -E '^(Authority|TeamIdentifier|Signature|Identifier)=' || true
codesign -d -r- "${APP_OUT}" 2>&1 | tail -3
codesign --verify --deep --strict "${APP_OUT}"

cd "${OUT_DIR}"
ditto -c -k --sequesterRsrc --keepParent "${APP_NAME}.app" "${ZIP_NAME}"

echo "Ready: ${OUT_DIR}/${ZIP_NAME}"
ls -lh "${OUT_DIR}/${ZIP_NAME}"
