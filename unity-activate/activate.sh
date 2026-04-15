#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────────────────
#  🐸 FrogitudeCI — Unity License Activation Script  (v1)
#
#  Activates Unity Personal (.ulf), Pro (serial), or License Server inside Docker.
#  Creates a shared Docker volume for license persistence across steps.
#  Compatible with Unity 5.x → Unity 6+.
#
#  Required env:  UNITY_VERSION, GITHUB_RUN_ID
#  License env:   UNITY_LICENSE (Personal)
#                 OR UNITY_SERIAL + UNITY_EMAIL + UNITY_PASSWORD (Pro)
#                 OR UNITY_LICENSING_SERVER (floating license)
#  Optional env:  DOCKER_IMAGE_OVERRIDE, CONTAINER_REGISTRY, CONTAINER_REGISTRY_VERSION
# ────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Validate inputs ──────────────────────────────────────────────────────
if [[ -z "${UNITY_VERSION:-}" ]]; then
  echo "::error::unity-version is required"
  exit 1
fi

if [[ -z "${UNITY_LICENSE:-}" && -z "${UNITY_SERIAL:-}" && -z "${UNITY_LICENSING_SERVER:-}" ]]; then
  echo "::error::Either license (.ulf content), serial number, or licensing-server URL must be provided"
  exit 1
fi

if [[ -n "${UNITY_SERIAL:-}" && ( -z "${UNITY_EMAIL:-}" || -z "${UNITY_PASSWORD:-}" ) ]]; then
  echo "::error::Serial activation requires email and password"
  exit 1
fi

# ── Determine Docker image ───────────────────────────────────────────────
REGISTRY="${CONTAINER_REGISTRY:-unityci/editor}"
REGISTRY_VERSION="${CONTAINER_REGISTRY_VERSION:-3}"
IMAGE="${DOCKER_IMAGE_OVERRIDE:-${REGISTRY}:${UNITY_VERSION}-base-${REGISTRY_VERSION}}"
VOLUME_NAME="unity-license-${GITHUB_RUN_ID}"
LICENSE_DIR="/root/.local/share/unity3d/Unity"

echo "🐸 Unity Activate"
echo "   Version : ${UNITY_VERSION}"
echo "   Image   : ${IMAGE}"
echo "   Volume  : ${VOLUME_NAME}"
if [[ -n "${UNITY_LICENSING_SERVER:-}" ]]; then
  echo "   Method  : License Server (floating)"
elif [[ -n "${UNITY_LICENSE:-}" ]]; then
  echo "   Method  : Personal (.ulf)"
else
  echo "   Method  : Pro (serial)"
fi

# ── Pull image ───────────────────────────────────────────────────────────
echo "::group::Pull Docker image"
docker pull "${IMAGE}"
echo "::endgroup::"

# ── Create volume ────────────────────────────────────────────────────────
docker volume create "${VOLUME_NAME}" > /dev/null
echo "::group::Activate license"

if [[ -n "${UNITY_LICENSING_SERVER:-}" ]]; then
  # ── License Server (floating license) ──────────────────────────────
  echo "Using Unity License Server: ${UNITY_LICENSING_SERVER}"

  docker run --rm \
    -v "${VOLUME_NAME}:${LICENSE_DIR}" \
    "${IMAGE}" \
    unity-editor \
      -quit \
      -batchmode \
      -nographics \
      -logFile /dev/stdout \
    || ACTIVATE_EXIT=$?

  # For license server, Unity acquires a floating license automatically
  # when the server URL is provided in the environment or services config.
  # The volume stores the session token for reuse across steps.
  if [[ "${ACTIVATE_EXIT:-0}" -ne 0 && "${ACTIVATE_EXIT:-0}" -ne 1 ]]; then
    echo "::error::Unity License Server activation failed (exit code ${ACTIVATE_EXIT})"
    echo "Common causes:"
    echo "  - License server URL is unreachable"
    echo "  - No available floating licenses on the server"
    docker volume rm "${VOLUME_NAME}" > /dev/null 2>&1 || true
    exit "${ACTIVATE_EXIT}"
  fi

elif [[ -n "${UNITY_LICENSE:-}" ]]; then
  # ── Personal license (.ulf file) ─────────────────────────────────────
  ULF_FILE="$(mktemp /tmp/unity-XXXXXX.ulf)"
  # Write license content (mask it from logs)
  echo "::add-mask::${UNITY_LICENSE:0:40}"
  printf '%s' "${UNITY_LICENSE}" > "${ULF_FILE}"

  docker run --rm \
    -v "${VOLUME_NAME}:${LICENSE_DIR}" \
    -v "${ULF_FILE}:/tmp/unity.ulf:ro" \
    "${IMAGE}" \
    unity-editor \
      -quit \
      -batchmode \
      -nographics \
      -manualLicenseFile /tmp/unity.ulf \
      -logFile /dev/stdout \
    || ACTIVATE_EXIT=$?

  rm -f "${ULF_FILE}"

  if [[ "${ACTIVATE_EXIT:-0}" -ne 0 ]]; then
    echo "::error::Unity Personal license activation failed (exit code ${ACTIVATE_EXIT})"
    echo "Common causes:"
    echo "  - .ulf file is expired or for a different Unity version"
    echo "  - .ulf file content is malformed (check for trailing whitespace)"
    docker volume rm "${VOLUME_NAME}" > /dev/null 2>&1 || true
    exit "${ACTIVATE_EXIT}"
  fi

else
  # ── Pro/Plus license (serial number) ─────────────────────────────────
  echo "::add-mask::${UNITY_SERIAL}"
  echo "::add-mask::${UNITY_PASSWORD}"

  docker run --rm \
    -v "${VOLUME_NAME}:${LICENSE_DIR}" \
    "${IMAGE}" \
    unity-editor \
      -quit \
      -batchmode \
      -nographics \
      -serial "${UNITY_SERIAL}" \
      -username "${UNITY_EMAIL}" \
      -password "${UNITY_PASSWORD}" \
      -logFile /dev/stdout \
    || ACTIVATE_EXIT=$?

  if [[ "${ACTIVATE_EXIT:-0}" -ne 0 ]]; then
    echo "::error::Unity Pro license activation failed (exit code ${ACTIVATE_EXIT})"
    echo "Common causes:"
    echo "  - Serial number is invalid or already in use on another machine"
    echo "  - Email/password credentials are incorrect"
    echo "  - Unity account does not have an active subscription"
    docker volume rm "${VOLUME_NAME}" > /dev/null 2>&1 || true
    exit "${ACTIVATE_EXIT}"
  fi
fi

echo "::endgroup::"
echo "✅ Unity license activated successfully"

# ── Set outputs ──────────────────────────────────────────────────────────
echo "volume-name=${VOLUME_NAME}" >> "${GITHUB_OUTPUT}"
