#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────────────────
#  🐸 FrogitudeCI — Unity License Activation Script
#
#  Activates Unity Personal (.ulf) or Pro (serial) license inside Docker.
#  Creates a shared Docker volume for license persistence across steps.
#
#  Required env:  UNITY_VERSION, GITHUB_RUN_ID
#  License env:   UNITY_LICENSE (Personal) OR UNITY_SERIAL + UNITY_EMAIL + UNITY_PASSWORD (Pro)
#  Optional env:  DOCKER_IMAGE_OVERRIDE
# ────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Validate inputs ──────────────────────────────────────────────────────
if [[ -z "${UNITY_VERSION:-}" ]]; then
  echo "::error::unity-version is required"
  exit 1
fi

if [[ -z "${UNITY_LICENSE:-}" && -z "${UNITY_SERIAL:-}" ]]; then
  echo "::error::Either license (.ulf content) or serial number must be provided"
  exit 1
fi

if [[ -n "${UNITY_SERIAL:-}" && ( -z "${UNITY_EMAIL:-}" || -z "${UNITY_PASSWORD:-}" ) ]]; then
  echo "::error::Serial activation requires email and password"
  exit 1
fi

# ── Determine Docker image ───────────────────────────────────────────────
IMAGE="${DOCKER_IMAGE_OVERRIDE:-unityci/editor:${UNITY_VERSION}-base-3}"
VOLUME_NAME="unity-license-${GITHUB_RUN_ID}"
LICENSE_DIR="/root/.local/share/unity3d/Unity"

echo "🐸 Unity Activate"
echo "   Version : ${UNITY_VERSION}"
echo "   Image   : ${IMAGE}"
echo "   Volume  : ${VOLUME_NAME}"
echo "   Method  : $([ -n "${UNITY_LICENSE:-}" ] && echo "Personal (.ulf)" || echo "Pro (serial)")"

# ── Pull image ───────────────────────────────────────────────────────────
echo "::group::Pull Docker image"
docker pull "${IMAGE}"
echo "::endgroup::"

# ── Create volume ────────────────────────────────────────────────────────
docker volume create "${VOLUME_NAME}" > /dev/null
echo "::group::Activate license"

if [[ -n "${UNITY_LICENSE:-}" ]]; then
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
