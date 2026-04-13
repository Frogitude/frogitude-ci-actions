#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────────────────
#  🐸 FrogitudeCI — Steam Deploy Script
#
#  Installs steamcmd, decodes config VDF for auth, generates app build VDF,
#  and pushes builds to Steamworks.
#
#  Required env:  STEAM_USERNAME, STEAM_CONFIG_VDF, STEAM_APP_ID
#  Optional env:  BUILD_DESCRIPTION, RELEASE_BRANCH, ROOT_PATH,
#                 DEPOT_1_PATH through DEPOT_5_PATH
# ────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Validate inputs ──────────────────────────────────────────────────────
if [[ -z "${STEAM_USERNAME:-}" ]]; then
  echo "::error::username is required"
  exit 1
fi
if [[ -z "${STEAM_CONFIG_VDF:-}" ]]; then
  echo "::error::config-vdf (base64) is required"
  exit 1
fi
if [[ -z "${STEAM_APP_ID:-}" ]]; then
  echo "::error::app-id is required"
  exit 1
fi

# ── Defaults ─────────────────────────────────────────────────────────────
ROOT_PATH="${ROOT_PATH:-build}"
RELEASE_BRANCH="${RELEASE_BRANCH:-prerelease}"
BUILD_DESCRIPTION="${BUILD_DESCRIPTION:-FrogitudeCI build $(date -u +%Y-%m-%d_%H%M%S)}"
WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"

echo "🐸 Steam Deploy"
echo "   Username : ${STEAM_USERNAME}"
echo "   App ID   : ${STEAM_APP_ID}"
echo "   Branch   : ${RELEASE_BRANCH}"
echo "   Root     : ${ROOT_PATH}"
echo "::add-mask::${STEAM_CONFIG_VDF:0:40}"

# ── Install steamcmd ─────────────────────────────────────────────────────
echo "::group::Install steamcmd"

if ! command -v steamcmd &> /dev/null; then
  echo "Installing steamcmd..."
  sudo dpkg --add-architecture i386
  echo steam steam/question select "I AGREE" | sudo debconf-set-selections
  echo steam steam/license note '' | sudo debconf-set-selections
  sudo apt-get update -qq
  sudo apt-get install -y -qq steamcmd lib32gcc-s1 > /dev/null 2>&1
  # Symlink to PATH if installed to /usr/games
  if [[ -f /usr/games/steamcmd ]]; then
    sudo ln -sf /usr/games/steamcmd /usr/local/bin/steamcmd
  fi
  echo "✅ steamcmd installed"
else
  echo "✅ steamcmd already available"
fi

echo "::endgroup::"

# ── Decode config VDF ────────────────────────────────────────────────────
echo "::group::Configure Steam authentication"

STEAM_HOME="${HOME}/.steam"
CONFIG_DIR="${STEAM_HOME}/config"
mkdir -p "${CONFIG_DIR}"

echo "${STEAM_CONFIG_VDF}" | base64 --decode > "${CONFIG_DIR}/config.vdf"
chmod 600 "${CONFIG_DIR}/config.vdf"
echo "✅ Steam config.vdf decoded"

echo "::endgroup::"

# ── Generate app build VDF ───────────────────────────────────────────────
echo "::group::Generate build manifest"

BUILD_VDF="/tmp/app_build_${STEAM_APP_ID}.vdf"
DEPOT_INDEX=0

cat > "${BUILD_VDF}" << EOF
"AppBuild"
{
  "AppID" "${STEAM_APP_ID}"
  "Desc" "${BUILD_DESCRIPTION}"
  "SetLive" "${RELEASE_BRANCH}"
  "ContentRoot" "${WORKSPACE}/${ROOT_PATH}"
  "BuildOutput" "/tmp/steam_build_output"
  "Depots"
  {
EOF

# Add each non-empty depot
for i in 1 2 3 4 5; do
  DEPOT_VAR="DEPOT_${i}_PATH"
  DEPOT_PATH="${!DEPOT_VAR:-}"
  if [[ -n "${DEPOT_PATH}" ]]; then
    DEPOT_ID=$((STEAM_APP_ID + i))
    cat >> "${BUILD_VDF}" << DEPOT
    "${DEPOT_ID}"
    {
      "FileMapping"
      {
        "LocalPath" "${DEPOT_PATH}/*"
        "DepotPath" "."
        "recursive" "1"
      }
    }
DEPOT
    DEPOT_INDEX=$((DEPOT_INDEX + 1))
    echo "   Depot ${DEPOT_ID}: ${DEPOT_PATH}"
  fi
done

# If no depots specified, use root path as single depot
if [[ ${DEPOT_INDEX} -eq 0 ]]; then
  DEPOT_ID=$((STEAM_APP_ID + 1))
  cat >> "${BUILD_VDF}" << DEPOT
    "${DEPOT_ID}"
    {
      "FileMapping"
      {
        "LocalPath" "*"
        "DepotPath" "."
        "recursive" "1"
      }
    }
DEPOT
  echo "   Depot ${DEPOT_ID}: (root)"
fi

echo '  }' >> "${BUILD_VDF}"
echo '}' >> "${BUILD_VDF}"

mkdir -p /tmp/steam_build_output
echo "✅ Build manifest generated: ${BUILD_VDF}"
echo "::endgroup::"

# ── Upload to Steam ──────────────────────────────────────────────────────
echo "::group::Upload to Steamworks"

DEPLOY_EXIT=0
steamcmd \
  +login "${STEAM_USERNAME}" \
  +run_app_build "${BUILD_VDF}" \
  +quit \
  || DEPLOY_EXIT=$?

echo "::endgroup::"

# ── Cleanup sensitive files ──────────────────────────────────────────────
rm -f "${CONFIG_DIR}/config.vdf"
rm -f "${BUILD_VDF}"

if [[ ${DEPLOY_EXIT} -ne 0 ]]; then
  echo "::error::Steam deploy failed (exit code ${DEPLOY_EXIT})"
  echo "Common causes:"
  echo "  - config.vdf is expired (re-generate with: steamcmd +login USERNAME +quit)"
  echo "  - App ID ${STEAM_APP_ID} does not exist or account lacks publish rights"
  echo "  - Depot IDs don't match your Steamworks app configuration"
  echo "  - Build content is empty or paths are wrong"
  exit ${DEPLOY_EXIT}
fi

echo "✅ Successfully deployed to Steam (App ${STEAM_APP_ID}, branch: ${RELEASE_BRANCH})"
