#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────────────────
#  🐸 FrogitudeCI — Unity Build Script
#
#  Builds Unity project inside Docker container for specified target platform.
#  Auto-selects correct Docker image tag per platform.
#
#  Required env:  UNITY_VERSION, TARGET_PLATFORM, LICENSE_VOLUME
#  Optional env:  PROJECT_PATH, BUILD_NAME, BUILD_PATH, BUILD_METHOD, IL2CPP,
#                 ANDROID_KEYSTORE_BASE64, ANDROID_KEYSTORE_PASS,
#                 ANDROID_KEYALIAS_NAME, ANDROID_KEYALIAS_PASS,
#                 DOCKER_IMAGE_OVERRIDE
# ────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────
PROJECT_PATH="${PROJECT_PATH:-.}"
BUILD_PATH="${BUILD_PATH:-build}"
BUILD_NAME="${BUILD_NAME:-$(basename "${GITHUB_REPOSITORY:-game}")}"
IL2CPP="${IL2CPP:-false}"
LICENSE_DIR="/root/.local/share/unity3d/Unity"
WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"

# ── Platform → Docker image tag mapping ──────────────────────────────────
resolve_image_tag() {
  local platform="$1"
  case "${platform}" in
    StandaloneWindows64)     echo "windows-mono-3" ;;
    StandaloneWindows)       echo "windows-mono-3" ;;
    StandaloneOSX)           echo "mac-mono-3" ;;
    StandaloneLinux64)       echo "linux-il2cpp-3" ;;
    Android)                 echo "android-3" ;;
    iOS)                     echo "ios-3" ;;
    WebGL)                   echo "webgl-3" ;;
    LinuxHeadlessSimulation) echo "linux-il2cpp-3" ;;
    *)
      echo "::error::Unknown target platform: ${platform}"
      echo "Supported: StandaloneWindows64, StandaloneOSX, StandaloneLinux64, Android, iOS, WebGL, LinuxHeadlessSimulation"
      exit 1
      ;;
  esac
}

IMAGE_TAG="$(resolve_image_tag "${TARGET_PLATFORM}")"
IMAGE="${DOCKER_IMAGE_OVERRIDE:-unityci/editor:${UNITY_VERSION}-${IMAGE_TAG}}"

echo "🐸 Unity Build"
echo "   Version  : ${UNITY_VERSION}"
echo "   Platform : ${TARGET_PLATFORM}"
echo "   Image    : ${IMAGE}"
echo "   Project  : ${PROJECT_PATH}"
echo "   Output   : ${BUILD_PATH}/${BUILD_NAME}"
echo "   IL2CPP   : ${IL2CPP}"
[[ -n "${BUILD_METHOD}" ]] && echo "   Method   : ${BUILD_METHOD}"

# ── Pull image ───────────────────────────────────────────────────────────
echo "::group::Pull Docker image"
docker pull "${IMAGE}"
echo "::endgroup::"

# ── Prepare build directory ──────────────────────────────────────────────
mkdir -p "${WORKSPACE}/${BUILD_PATH}"

# ── Build Docker args ────────────────────────────────────────────────────
DOCKER_ARGS=(
  --rm
  -v "${LICENSE_VOLUME}:${LICENSE_DIR}"
  -v "${WORKSPACE}/${PROJECT_PATH}:/project"
  -v "${WORKSPACE}/${BUILD_PATH}:/build"
  -w /project
)

# ── Android keystore ─────────────────────────────────────────────────────
if [[ "${TARGET_PLATFORM}" == "Android" && -n "${ANDROID_KEYSTORE_BASE64:-}" ]]; then
  echo "::group::Decode Android keystore"
  KEYSTORE_FILE="${WORKSPACE}/.keystore"
  echo "::add-mask::${ANDROID_KEYSTORE_PASS:-}"
  echo "::add-mask::${ANDROID_KEYALIAS_PASS:-}"
  echo "${ANDROID_KEYSTORE_BASE64}" | base64 --decode > "${KEYSTORE_FILE}"
  DOCKER_ARGS+=(-v "${KEYSTORE_FILE}:/keystore.jks:ro")
  DOCKER_ARGS+=(
    -e "ANDROID_KEYSTORE_NAME=/keystore.jks"
    -e "ANDROID_KEYSTORE_PASS=${ANDROID_KEYSTORE_PASS:-}"
    -e "ANDROID_KEYALIAS_NAME=${ANDROID_KEYALIAS_NAME:-}"
    -e "ANDROID_KEYALIAS_PASS=${ANDROID_KEYALIAS_PASS:-}"
  )
  echo "✅ Android keystore decoded"
  echo "::endgroup::"
fi

# ── Compose Unity build command ──────────────────────────────────────────
UNITY_ARGS=(
  unity-editor
  -quit
  -batchmode
  -nographics
  -buildTarget "${TARGET_PLATFORM}"
  -logFile /dev/stdout
)

if [[ -n "${BUILD_METHOD:-}" ]]; then
  # Custom build method
  UNITY_ARGS+=(-executeMethod "${BUILD_METHOD}")
else
  # Default: use -buildPath for standalone, or let Unity auto-build
  case "${TARGET_PLATFORM}" in
    StandaloneWindows64|StandaloneWindows)
      UNITY_ARGS+=(-buildWindows64Player "/build/${BUILD_NAME}/${BUILD_NAME}.exe")
      ;;
    StandaloneOSX)
      UNITY_ARGS+=(-buildOSXUniversalPlayer "/build/${BUILD_NAME}/${BUILD_NAME}.app")
      ;;
    StandaloneLinux64|LinuxHeadlessSimulation)
      UNITY_ARGS+=(-buildLinux64Player "/build/${BUILD_NAME}/${BUILD_NAME}")
      ;;
    Android)
      UNITY_ARGS+=(-executeMethod "UnityEditor.BuildPlayerWindow.BuildPlayerAndRun" -buildTarget Android)
      # Android outputs go to /build via custom build script or default
      ;;
    iOS)
      UNITY_ARGS+=(-buildTarget iOS)
      ;;
    WebGL)
      UNITY_ARGS+=(-executeMethod "UnityEditor.BuildPlayerWindow.BuildPlayerAndRun" -buildTarget WebGL)
      ;;
  esac
fi

# ── IL2CPP override ──────────────────────────────────────────────────────
if [[ "${IL2CPP}" == "true" ]]; then
  DOCKER_ARGS+=(-e "SCRIPTING_BACKEND=IL2CPP")
fi

# ── Run build ────────────────────────────────────────────────────────────
echo "::group::Build Unity project"
BUILD_EXIT=0

docker run "${DOCKER_ARGS[@]}" "${IMAGE}" "${UNITY_ARGS[@]}" || BUILD_EXIT=$?

echo "::endgroup::"

# ── Cleanup ──────────────────────────────────────────────────────────────
[[ -f "${WORKSPACE}/.keystore" ]] && rm -f "${WORKSPACE}/.keystore"

if [[ ${BUILD_EXIT} -ne 0 ]]; then
  echo "::error::Unity build failed for ${TARGET_PLATFORM} (exit code ${BUILD_EXIT})"
  echo "Common causes:"
  echo "  - Missing build support module for ${TARGET_PLATFORM}"
  echo "  - Compilation errors in project scripts"
  echo "  - Insufficient disk space for build"
  exit ${BUILD_EXIT}
fi

# ── Calculate output size ────────────────────────────────────────────────
BUILD_SIZE="$(du -sh "${WORKSPACE}/${BUILD_PATH}" 2>/dev/null | cut -f1 || echo "unknown")"
echo "✅ Build completed: ${BUILD_PATH} (${BUILD_SIZE})"

# ── Set outputs ──────────────────────────────────────────────────────────
{
  echo "build-path=${BUILD_PATH}"
  echo "build-size=${BUILD_SIZE}"
} >> "${GITHUB_OUTPUT}"
