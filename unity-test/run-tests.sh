#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────────────────
#  🐸 FrogitudeCI — Unity Test Runner Script  (v1)
#
#  Runs Unity Edit-mode, Play-mode, and/or Standalone tests inside Docker.
#  Parses NUnit XML results and sets GitHub Actions outputs.
#  Supports code coverage, custom parameters, package mode, and host network.
#
#  Required env:  UNITY_VERSION, LICENSE_VOLUME
#  Optional env:  PROJECT_PATH, TEST_MODE, ARTIFACTS_PATH, COVERAGE,
#                 COVERAGE_OPTIONS, CUSTOM_PARAMETERS, PACKAGE_MODE,
#                 USE_HOST_NETWORK, DOCKER_IMAGE_OVERRIDE,
#                 CONTAINER_REGISTRY, CONTAINER_REGISTRY_VERSION,
#                 DOCKER_CPU_LIMIT, DOCKER_MEMORY_LIMIT,
#                 SSH_AGENT, GIT_PRIVATE_TOKEN, RUN_AS_HOST_USER,
#                 UNITY_LICENSING_SERVER
# ────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────
PROJECT_PATH="${PROJECT_PATH:-.}"
TEST_MODE="${TEST_MODE:-all}"
ARTIFACTS_PATH="${ARTIFACTS_PATH:-test-results}"
COVERAGE="${COVERAGE:-false}"
COVERAGE_OPTIONS="${COVERAGE_OPTIONS:-generateAdditionalMetrics;generateHtmlReport;generateBadgeReport}"
PACKAGE_MODE="${PACKAGE_MODE:-false}"
USE_HOST_NETWORK="${USE_HOST_NETWORK:-false}"
RUN_AS_HOST_USER="${RUN_AS_HOST_USER:-false}"
REGISTRY="${CONTAINER_REGISTRY:-unityci/editor}"
REGISTRY_VERSION="${CONTAINER_REGISTRY_VERSION:-3}"
IMAGE="${DOCKER_IMAGE_OVERRIDE:-${REGISTRY}:${UNITY_VERSION}-base-${REGISTRY_VERSION}}"
LICENSE_DIR="/root/.local/share/unity3d/Unity"
WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"

echo "🐸 Unity Test Runner"
echo "   Version   : ${UNITY_VERSION}"
echo "   Image     : ${IMAGE}"
echo "   Mode      : ${TEST_MODE}"
echo "   Project   : ${PROJECT_PATH}"
echo "   Artifacts : ${ARTIFACTS_PATH}"
echo "   Coverage  : ${COVERAGE}"
echo "   Package   : ${PACKAGE_MODE}"
[[ -n "${CUSTOM_PARAMETERS:-}" ]] && echo "   Params    : ${CUSTOM_PARAMETERS}"

# ── Prepare output directory ─────────────────────────────────────────────
mkdir -p "${WORKSPACE}/${ARTIFACTS_PATH}"

# ── Build common Docker args ─────────────────────────────────────────────
COMMON_DOCKER_ARGS=(
  --rm
  -v "${LICENSE_VOLUME}:${LICENSE_DIR}"
  -v "${WORKSPACE}/${PROJECT_PATH}:/project"
  -v "${WORKSPACE}/${ARTIFACTS_PATH}:/results"
  -w /project
)

# Host network
if [[ "${USE_HOST_NETWORK}" == "true" ]]; then
  COMMON_DOCKER_ARGS+=(--network host)
fi

# Docker resource limits
if [[ -n "${DOCKER_CPU_LIMIT:-}" ]]; then
  COMMON_DOCKER_ARGS+=(--cpus "${DOCKER_CPU_LIMIT}")
fi
if [[ -n "${DOCKER_MEMORY_LIMIT:-}" ]]; then
  COMMON_DOCKER_ARGS+=(-m "${DOCKER_MEMORY_LIMIT}")
fi

# Run as host user (self-hosted runners)
if [[ "${RUN_AS_HOST_USER}" == "true" ]]; then
  COMMON_DOCKER_ARGS+=(--user "$(id -u):$(id -g)")
fi

# SSH agent forwarding
if [[ -n "${SSH_AGENT:-}" ]]; then
  COMMON_DOCKER_ARGS+=(
    -v "${SSH_AGENT}:/ssh-agent"
    -e "SSH_AUTH_SOCK=/ssh-agent"
  )
fi

# Git private token
if [[ -n "${GIT_PRIVATE_TOKEN:-}" ]]; then
  COMMON_DOCKER_ARGS+=(-e "GIT_PRIVATE_TOKEN=${GIT_PRIVATE_TOKEN}")
fi

# Unity License Server
if [[ -n "${UNITY_LICENSING_SERVER:-}" ]]; then
  COMMON_DOCKER_ARGS+=(-e "UNITY_LICENSING_SERVER=${UNITY_LICENSING_SERVER}")
fi

# ── Build test arguments ─────────────────────────────────────────────────
run_test_mode() {
  local mode="$1"
  local result_file="${WORKSPACE}/${ARTIFACTS_PATH}/${mode}-results.xml"
  local log_file="${WORKSPACE}/${ARTIFACTS_PATH}/${mode}.log"

  echo "::group::Run ${mode} tests"
  echo "🧪 Running ${mode} tests..."

  local coverage_args=""
  if [[ "${COVERAGE}" == "true" ]]; then
    coverage_args="-enableCodeCoverage -coverageResultsPath /results/coverage -coverageOptions ${COVERAGE_OPTIONS}"
  fi

  local custom_args=""
  if [[ -n "${CUSTOM_PARAMETERS:-}" ]]; then
    custom_args="${CUSTOM_PARAMETERS}"
  fi

  local exit_code=0
  # shellcheck disable=SC2086
  docker run "${COMMON_DOCKER_ARGS[@]}" \
    "${IMAGE}" \
    unity-editor \
      -batchmode \
      -nographics \
      -runTests \
      -testPlatform "${mode}" \
      -testResults "/results/${mode}-results.xml" \
      -logFile "/results/${mode}.log" \
      ${coverage_args} \
      ${custom_args} \
    || exit_code=$?

  echo "::endgroup::"

  if [[ ${exit_code} -eq 0 ]]; then
    echo "✅ ${mode} tests passed"
  elif [[ ${exit_code} -eq 2 ]]; then
    echo "⚠️  ${mode} tests had failures (exit code 2)"
  else
    echo "::error::${mode} tests crashed (exit code ${exit_code})"
  fi

  return ${exit_code}
}

# ── Run tests ────────────────────────────────────────────────────────────
OVERALL_EXIT=0

case "${TEST_MODE}" in
  all)
    run_test_mode "EditMode" || OVERALL_EXIT=$?
    run_test_mode "PlayMode" || OVERALL_EXIT=$?
    ;;
  editmode|EditMode)
    run_test_mode "EditMode" || OVERALL_EXIT=$?
    ;;
  playmode|PlayMode)
    run_test_mode "PlayMode" || OVERALL_EXIT=$?
    ;;
  standalone|Standalone)
    run_test_mode "Standalone" || OVERALL_EXIT=$?
    ;;
  *)
    echo "::error::Invalid test-mode '${TEST_MODE}'. Use: all, editmode, playmode, or standalone"
    exit 1
    ;;
esac

# ── Parse results ────────────────────────────────────────────────────────
echo "::group::Parse test results"

TOTAL=0
PASSED=0
FAILED=0
SKIPPED=0

for xml_file in "${WORKSPACE}/${ARTIFACTS_PATH}"/*-results.xml; do
  [[ -f "${xml_file}" ]] || continue
  echo "📄 Parsing: $(basename "${xml_file}")"

  # NUnit XML format: <test-run total="N" passed="N" failed="N" skipped="N" ...>
  file_total=$(grep -oP 'total="\K[0-9]+' "${xml_file}" | head -1 || echo "0")
  file_passed=$(grep -oP 'passed="\K[0-9]+' "${xml_file}" | head -1 || echo "0")
  file_failed=$(grep -oP 'failed="\K[0-9]+' "${xml_file}" | head -1 || echo "0")
  file_skipped=$(grep -oP '(?:skipped|inconclusive)="\K[0-9]+' "${xml_file}" | head -1 || echo "0")

  TOTAL=$((TOTAL + file_total))
  PASSED=$((PASSED + file_passed))
  FAILED=$((FAILED + file_failed))
  SKIPPED=$((SKIPPED + file_skipped))

  echo "   Total: ${file_total} | Passed: ${file_passed} | Failed: ${file_failed} | Skipped: ${file_skipped}"
done

echo ""
echo "📊 Summary: ${TOTAL} total, ${PASSED} passed, ${FAILED} failed, ${SKIPPED} skipped"
echo "::endgroup::"

# ── Set outputs ──────────────────────────────────────────────────────────
{
  echo "results-path=${ARTIFACTS_PATH}"
  echo "total=${TOTAL}"
  echo "passed=${PASSED}"
  echo "failed=${FAILED}"
  echo "skipped=${SKIPPED}"
  if [[ "${COVERAGE}" == "true" ]]; then
    echo "coverage-path=${ARTIFACTS_PATH}/coverage"
  fi
} >> "${GITHUB_OUTPUT}"

# ── Exit with appropriate code ───────────────────────────────────────────
if [[ ${FAILED} -gt 0 ]]; then
  echo "::error::${FAILED} test(s) failed"
  exit 2
fi

exit ${OVERALL_EXIT}
