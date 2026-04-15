#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────────────────
#  🐸 FrogitudeCI — Unity Build Script  (v1)
#
#  Builds Unity project inside Docker container for specified target platform.
#  Auto-selects correct Docker image tag per platform.
#  Supports Build Profiles, versioning, custom parameters, and extended
#  Android options (APK/AAB/Android Studio, target SDK, symbols).
#
#  Required env:  UNITY_VERSION, TARGET_PLATFORM, LICENSE_VOLUME
#  Optional env:  PROJECT_PATH, BUILD_NAME, BUILD_PATH, BUILD_METHOD,
#                 BUILD_PROFILE, CUSTOM_PARAMETERS, VERSIONING, VERSION,
#                 IL2CPP, ENABLE_GPU, ALLOW_DIRTY_BUILD,
#                 ANDROID_EXPORT_TYPE, ANDROID_KEYSTORE_BASE64,
#                 ANDROID_KEYSTORE_PASS, ANDROID_KEYALIAS_NAME,
#                 ANDROID_KEYALIAS_PASS, ANDROID_TARGET_SDK_VERSION,
#                 ANDROID_SYMBOL_TYPE, DOCKER_IMAGE_OVERRIDE,
#                 CONTAINER_REGISTRY, CONTAINER_REGISTRY_VERSION,
#                 DOCKER_CPU_LIMIT, DOCKER_MEMORY_LIMIT,
#                 SSH_AGENT, GIT_PRIVATE_TOKEN, RUN_AS_HOST_USER,
#                 UNITY_LICENSING_SERVER
# ────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────
PROJECT_PATH="${PROJECT_PATH:-.}"
BUILD_PATH="${BUILD_PATH:-build}"
BUILD_NAME="${BUILD_NAME:-$(basename "${GITHUB_REPOSITORY:-game}")}"
IL2CPP="${IL2CPP:-false}"
ENABLE_GPU="${ENABLE_GPU:-false}"
ALLOW_DIRTY_BUILD="${ALLOW_DIRTY_BUILD:-false}"
RUN_AS_HOST_USER="${RUN_AS_HOST_USER:-false}"
ANDROID_EXPORT_TYPE="${ANDROID_EXPORT_TYPE:-androidPackage}"
ANDROID_SYMBOL_TYPE="${ANDROID_SYMBOL_TYPE:-none}"
LICENSE_DIR="/root/.local/share/unity3d/Unity"
WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"
REGISTRY="${CONTAINER_REGISTRY:-unityci/editor}"
REGISTRY_VERSION="${CONTAINER_REGISTRY_VERSION:-3}"

# ── Platform → Docker image tag mapping ──────────────────────────────────
resolve_image_tag() {
  local platform="$1"
  case "${platform}" in
    StandaloneWindows64)     echo "windows-mono-${REGISTRY_VERSION}" ;;
    StandaloneWindows)       echo "windows-mono-${REGISTRY_VERSION}" ;;
    StandaloneOSX)           echo "mac-mono-${REGISTRY_VERSION}" ;;
    StandaloneLinux64)       echo "linux-il2cpp-${REGISTRY_VERSION}" ;;
    Android)                 echo "android-${REGISTRY_VERSION}" ;;
    iOS)                     echo "ios-${REGISTRY_VERSION}" ;;
    WebGL)                   echo "webgl-${REGISTRY_VERSION}" ;;
    LinuxHeadlessSimulation) echo "linux-il2cpp-${REGISTRY_VERSION}" ;;
    tvOS)                    echo "appletv-${REGISTRY_VERSION}" ;;
    WSAPlayer)               echo "universal-windows-platform-${REGISTRY_VERSION}" ;;
    *)
      echo "::error::Unknown target platform: ${platform}"
      echo "Supported: StandaloneWindows64, StandaloneWindows, StandaloneOSX, StandaloneLinux64, Android, iOS, WebGL, LinuxHeadlessSimulation, tvOS, WSAPlayer"
      exit 1
      ;;
  esac
}

IMAGE_TAG="$(resolve_image_tag "${TARGET_PLATFORM}")"
IMAGE="${DOCKER_IMAGE_OVERRIDE:-${REGISTRY}:${UNITY_VERSION}-${IMAGE_TAG}}"

echo "🐸 Unity Build"
echo "   Version  : ${UNITY_VERSION}"
echo "   Platform : ${TARGET_PLATFORM}"
echo "   Image    : ${IMAGE}"
echo "   Project  : ${PROJECT_PATH}"
echo "   Output   : ${BUILD_PATH}/${BUILD_NAME}"
echo "   IL2CPP   : ${IL2CPP}"
echo "   GPU      : ${ENABLE_GPU}"
[[ -n "${BUILD_METHOD:-}" ]] && echo "   Method   : ${BUILD_METHOD}"
[[ -n "${BUILD_PROFILE:-}" ]] && echo "   Profile  : ${BUILD_PROFILE}"
[[ -n "${VERSIONING:-}" ]] && echo "   Version  : ${VERSIONING} ${VERSION:-}"
[[ -n "${CUSTOM_PARAMETERS:-}" ]] && echo "   Params   : ${CUSTOM_PARAMETERS}"
[[ "${TARGET_PLATFORM}" == "Android" ]] && echo "   Export   : ${ANDROID_EXPORT_TYPE}"

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

# ── Docker resource limits ───────────────────────────────────────────────
if [[ -n "${DOCKER_CPU_LIMIT:-}" ]]; then
  DOCKER_ARGS+=(--cpus "${DOCKER_CPU_LIMIT}")
fi
if [[ -n "${DOCKER_MEMORY_LIMIT:-}" ]]; then
  DOCKER_ARGS+=(-m "${DOCKER_MEMORY_LIMIT}")
fi

# ── Run as host user (self-hosted runners) ───────────────────────────────
if [[ "${RUN_AS_HOST_USER}" == "true" ]]; then
  DOCKER_ARGS+=(--user "$(id -u):$(id -g)")
fi

# ── SSH agent forwarding ─────────────────────────────────────────────────
if [[ -n "${SSH_AGENT:-}" ]]; then
  DOCKER_ARGS+=(
    -v "${SSH_AGENT}:/ssh-agent"
    -e "SSH_AUTH_SOCK=/ssh-agent"
  )
fi

# ── Git private token ────────────────────────────────────────────────────
if [[ -n "${GIT_PRIVATE_TOKEN:-}" ]]; then
  DOCKER_ARGS+=(-e "GIT_PRIVATE_TOKEN=${GIT_PRIVATE_TOKEN}")
fi

# ── Unity License Server ─────────────────────────────────────────────────
if [[ -n "${UNITY_LICENSING_SERVER:-}" ]]; then
  DOCKER_ARGS+=(-e "UNITY_LICENSING_SERVER=${UNITY_LICENSING_SERVER}")
fi

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
  -buildTarget "${TARGET_PLATFORM}"
  -logFile /dev/stdout
)

# GPU support
if [[ "${ENABLE_GPU}" != "true" ]]; then
  UNITY_ARGS+=(-nographics)
fi

# Build Profile (Unity 6+)
if [[ -n "${BUILD_PROFILE:-}" ]]; then
  UNITY_ARGS+=(-activeBuildProfile "${BUILD_PROFILE}")
fi

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
      ;;
    iOS)
      UNITY_ARGS+=(-buildTarget iOS)
      ;;
    WebGL)
      UNITY_ARGS+=(-executeMethod "UnityEditor.BuildPlayerWindow.BuildPlayerAndRun" -buildTarget WebGL)
      ;;
    tvOS)
      UNITY_ARGS+=(-buildTarget tvOS)
      ;;
    WSAPlayer)
      UNITY_ARGS+=(-buildTarget WSAPlayer)
      ;;
  esac
fi

# ── IL2CPP override ──────────────────────────────────────────────────────
if [[ "${IL2CPP}" == "true" ]]; then
  DOCKER_ARGS+=(-e "SCRIPTING_BACKEND=IL2CPP")
fi

# ── Android-specific options ─────────────────────────────────────────────
if [[ "${TARGET_PLATFORM}" == "Android" ]]; then
  DOCKER_ARGS+=(-e "ANDROID_EXPORT_TYPE=${ANDROID_EXPORT_TYPE}")
  if [[ -n "${ANDROID_TARGET_SDK_VERSION:-}" ]]; then
    DOCKER_ARGS+=(-e "ANDROID_TARGET_SDK_VERSION=${ANDROID_TARGET_SDK_VERSION}")
  fi
  if [[ "${ANDROID_SYMBOL_TYPE}" != "none" ]]; then
    DOCKER_ARGS+=(-e "ANDROID_SYMBOL_TYPE=${ANDROID_SYMBOL_TYPE}")
  fi
fi

# ── Custom parameters ────────────────────────────────────────────────────
if [[ -n "${CUSTOM_PARAMETERS:-}" ]]; then
  # shellcheck disable=SC2206
  UNITY_ARGS+=(${CUSTOM_PARAMETERS})
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
fi

# ── Calculate output size ────────────────────────────────────────────────
BUILD_SIZE="$(du -sh "${WORKSPACE}/${BUILD_PATH}" 2>/dev/null | cut -f1 || echo "unknown")"
echo "✅ Build completed: ${BUILD_PATH} (${BUILD_SIZE})"

# ── Set outputs ──────────────────────────────────────────────────────────
{
  echo "build-path=${BUILD_PATH}"
  echo "build-size=${BUILD_SIZE}"
  echo "build-version=${VERSION:-unknown}"
  echo "engine-exit-code=${BUILD_EXIT}"
} >> "${GITHUB_OUTPUT}"

exit ${BUILD_EXIT}
