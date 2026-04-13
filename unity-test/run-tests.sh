#!/usr/bin/env bash
# ────────────────────────────────────────────────────────────────────────────
#  🐸 FrogitudeCI — Unity Test Runner Script
#
#  Runs Unity Edit-mode and/or Play-mode tests inside Docker container.
#  Parses NUnit XML results and sets GitHub Actions outputs.
#
#  Required env:  UNITY_VERSION, LICENSE_VOLUME
#  Optional env:  PROJECT_PATH, TEST_MODE, ARTIFACTS_PATH, COVERAGE, DOCKER_IMAGE_OVERRIDE
# ────────────────────────────────────────────────────────────────────────────
set -euo pipefail

# ── Defaults ─────────────────────────────────────────────────────────────
PROJECT_PATH="${PROJECT_PATH:-.}"
TEST_MODE="${TEST_MODE:-all}"
ARTIFACTS_PATH="${ARTIFACTS_PATH:-test-results}"
COVERAGE="${COVERAGE:-false}"
IMAGE="${DOCKER_IMAGE_OVERRIDE:-unityci/editor:${UNITY_VERSION}-base-3}"
LICENSE_DIR="/root/.local/share/unity3d/Unity"
WORKSPACE="${GITHUB_WORKSPACE:-$(pwd)}"

echo "🐸 Unity Test Runner"
echo "   Version   : ${UNITY_VERSION}"
echo "   Image     : ${IMAGE}"
echo "   Mode      : ${TEST_MODE}"
echo "   Project   : ${PROJECT_PATH}"
echo "   Artifacts : ${ARTIFACTS_PATH}"
echo "   Coverage  : ${COVERAGE}"

# ── Prepare output directory ─────────────────────────────────────────────
mkdir -p "${WORKSPACE}/${ARTIFACTS_PATH}"

# ── Build test arguments ─────────────────────────────────────────────────
run_test_mode() {
  local mode="$1"
  local result_file="${WORKSPACE}/${ARTIFACTS_PATH}/${mode}-results.xml"
  local log_file="${WORKSPACE}/${ARTIFACTS_PATH}/${mode}.log"

  echo "::group::Run ${mode} tests"
  echo "🧪 Running ${mode} tests..."

  local coverage_args=""
  if [[ "${COVERAGE}" == "true" ]]; then
    coverage_args="-enableCodeCoverage -coverageResultsPath /results/coverage -coverageOptions generateAdditionalMetrics"
  fi

  local exit_code=0
  docker run --rm \
    -v "${LICENSE_VOLUME}:${LICENSE_DIR}" \
    -v "${WORKSPACE}/${PROJECT_PATH}:/project" \
    -v "${WORKSPACE}/${ARTIFACTS_PATH}:/results" \
    -w /project \
    "${IMAGE}" \
    unity-editor \
      -batchmode \
      -nographics \
      -runTests \
      -testPlatform "${mode}" \
      -testResults "/results/${mode}-results.xml" \
      -logFile "/results/${mode}.log" \
      ${coverage_args} \
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
  *)
    echo "::error::Invalid test-mode '${TEST_MODE}'. Use: all, editmode, or playmode"
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
} >> "${GITHUB_OUTPUT}"

# ── Exit with appropriate code ───────────────────────────────────────────
if [[ ${FAILED} -gt 0 ]]; then
  echo "::error::${FAILED} test(s) failed"
  exit 2
fi

exit ${OVERALL_EXIT}
