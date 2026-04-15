#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────────────────
#  🐸 FrogitudeCI — Unity Return License Script  (v1)
#
#  Returns a Unity Pro/Plus serial license via Docker.
#  This frees the seat so it can be used on another machine.
#
#  Required env:  UNITY_VERSION, LICENSE_VOLUME, UNITY_SERIAL
#  Optional env:  CONTAINER_REGISTRY, CONTAINER_REGISTRY_VERSION
# ────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Validate ─────────────────────────────────────────────────────────────
if [[ -z "${UNITY_SERIAL:-}" ]]; then
  echo "::warning::No serial provided — skipping license return (Personal/.ulf licenses don't need returning)"
  exit 0
fi

if [[ -z "${UNITY_VERSION:-}" ]]; then
  echo "::error::unity-version is required"
  exit 1
fi

if [[ -z "${LICENSE_VOLUME:-}" ]]; then
  echo "::error::license-volume is required"
  exit 1
fi

# ── Defaults ─────────────────────────────────────────────────────────────
REGISTRY="${CONTAINER_REGISTRY:-unityci/editor}"
REGISTRY_VERSION="${CONTAINER_REGISTRY_VERSION:-3}"
IMAGE="${REGISTRY}:${UNITY_VERSION}-base-${REGISTRY_VERSION}"
LICENSE_DIR="/root/.local/share/unity3d/Unity"

echo "🐸 Unity Return License"
echo "   Version : ${UNITY_VERSION}"
echo "   Image   : ${IMAGE}"
echo "::add-mask::${UNITY_SERIAL}"

# ── Return license ───────────────────────────────────────────────────────
echo "::group::Return Unity license"

RETURN_EXIT=0
docker run --rm \
  -v "${LICENSE_VOLUME}:${LICENSE_DIR}" \
  "${IMAGE}" \
  unity-editor \
    -batchmode \
    -nographics \
    -returnlicense \
    -serial "${UNITY_SERIAL}" \
    -logFile - \
  || RETURN_EXIT=$?

echo "::endgroup::"

# ── Cleanup volume ───────────────────────────────────────────────────────
echo "::group::Cleanup license volume"
docker volume rm "${LICENSE_VOLUME}" 2>/dev/null || true
echo "::endgroup::"

if [[ ${RETURN_EXIT} -ne 0 ]]; then
  echo "::warning::License return exited with code ${RETURN_EXIT} — seat may still be consumed"
  # Don't fail the workflow for license return issues
  exit 0
fi

echo "✅ Unity license returned successfully"
