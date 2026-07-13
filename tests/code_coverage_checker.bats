#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

setup() {
  export TEST_TMP_DIR
  TEST_TMP_DIR="$(mktemp -d)"

  export MOCK_BASE_BUILD="41"
  export MOCK_CURRENT_BUILD="42"
  export MOCK_BASE_DOWNLOAD_URL="https://example.com/base-coverage"
  export MOCK_CURRENT_DOWNLOAD_URL="https://example.com/current-coverage"

  export MOCK_BUILDS_RESPONSE="$TEST_TMP_DIR/builds_response.json"
  export MOCK_BASE_ARTIFACTS_RESPONSE="$TEST_TMP_DIR/base_artifacts_response.json"
  export MOCK_CURRENT_ARTIFACTS_RESPONSE="$TEST_TMP_DIR/current_artifacts_response.json"
  export MOCK_BASE_COVERAGE_JSON="$TEST_TMP_DIR/base_coverage.json"
  export MOCK_CURRENT_COVERAGE_JSON="$TEST_TMP_DIR/current_coverage.json"

  cat > "$MOCK_BUILDS_RESPONSE" <<'JSON'
[{"number":41}]
JSON

  cat > "$MOCK_BASE_ARTIFACTS_RESPONSE" <<'JSON'
[{"id":"1","path":"coverage/.last_run.json","download_url":"https://example.com/base-coverage"}]
JSON

  cat > "$MOCK_CURRENT_ARTIFACTS_RESPONSE" <<'JSON'
[{"id":"2","path":"coverage/.last_run.json","download_url":"https://example.com/current-coverage"}]
JSON

  mkdir -p "$TEST_TMP_DIR/fakebin"

  cat > "$TEST_TMP_DIR/fakebin/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail

args="$*"

if [[ "$args" == *"/builds?branch="*"state=passed"* ]]; then
  cat "$MOCK_BUILDS_RESPONSE"
  exit 0
fi

if [[ "$args" == *"/builds/$MOCK_BASE_BUILD/artifacts?page=1&per_page=100"* ]]; then
  cat "$MOCK_BASE_ARTIFACTS_RESPONSE"
  exit 0
fi

if [[ "$args" == *"/builds/$MOCK_CURRENT_BUILD/artifacts?page=1&per_page=100"* ]]; then
  cat "$MOCK_CURRENT_ARTIFACTS_RESPONSE"
  exit 0
fi

if [[ "$args" == *"$MOCK_BASE_DOWNLOAD_URL"* || "$args" == *"$MOCK_CURRENT_DOWNLOAD_URL"* ]]; then
  output_file=""
  while [[ $# -gt 0 ]]; do
    if [[ "$1" == "-o" ]]; then
      output_file="$2"
      break
    fi
    shift
  done

  if [[ -z "$output_file" ]]; then
    echo "curl stub expected -o argument" >&2
    exit 1
  fi

  if [[ "$args" == *"$MOCK_BASE_DOWNLOAD_URL"* ]]; then
    cat "$MOCK_BASE_COVERAGE_JSON" > "$output_file"
  else
    cat "$MOCK_CURRENT_COVERAGE_JSON" > "$output_file"
  fi

  exit 0
fi

echo "Unexpected curl invocation: $args" >&2
exit 1
SH

  chmod +x "$TEST_TMP_DIR/fakebin/curl"

  export PATH="$TEST_TMP_DIR/fakebin:$PATH"
  export BUILDKITE_API_TOKEN="token"
  export BUILDKITE_PIPELINE_SLUG="my-pipeline"
  export BASE_BRANCH="master"
  export BUILDKITE_BUILD_NUMBER="$MOCK_CURRENT_BUILD"
  export BASELINE_ARTIFACTS_JSON="$TEST_TMP_DIR/base_artifacts.json"
  export CURRENT_ARTIFACTS_JSON="$TEST_TMP_DIR/current_artifacts.json"
  export BASELINE_COVERAGE_FILE="$TEST_TMP_DIR/base_metrics.json"
  export CURRENT_COVERAGE_FILE="$TEST_TMP_DIR/current_metrics.json"
}

teardown() {
  rm -rf "$TEST_TMP_DIR"

  unset MOCK_BASE_BUILD MOCK_CURRENT_BUILD MOCK_BASE_DOWNLOAD_URL MOCK_CURRENT_DOWNLOAD_URL
  unset MOCK_BUILDS_RESPONSE MOCK_BASE_ARTIFACTS_RESPONSE MOCK_CURRENT_ARTIFACTS_RESPONSE
  unset MOCK_BASE_COVERAGE_JSON MOCK_CURRENT_COVERAGE_JSON
  unset BUILDKITE_API_TOKEN BUILDKITE_PIPELINE_SLUG BASE_BRANCH BUILDKITE_BUILD_NUMBER
  unset BASELINE_ARTIFACTS_JSON CURRENT_ARTIFACTS_JSON BASELINE_COVERAGE_FILE CURRENT_COVERAGE_FILE
  unset COVERAGE_TOLERANCE COVERAGE
}

@test "coverage checker passes when coverage drop is within COVERAGE_TOLERANCE" {
  cat > "$MOCK_BASE_COVERAGE_JSON" <<'JSON'
{"line":90.0}
JSON

  cat > "$MOCK_CURRENT_COVERAGE_JSON" <<'JSON'
{"line":89.2}
JSON

  export COVERAGE_TOLERANCE="1.0"

  run bash ./lib/code_coverage_checker.sh

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Minimum allowed coverage: 89.0000%"* ]]
  [[ "$output" == *"OK: PR coverage (89.2%) is within tolerance"* ]]
}

@test "coverage checker fails when coverage drop exceeds COVERAGE_TOLERANCE" {
  cat > "$MOCK_BASE_COVERAGE_JSON" <<'JSON'
{"line":90.0}
JSON

  cat > "$MOCK_CURRENT_COVERAGE_JSON" <<'JSON'
{"line":88.8}
JSON

  export COVERAGE_TOLERANCE="1.0"

  run bash ./lib/code_coverage_checker.sh

  [[ "$status" -eq 1 ]]
  [[ "$output" == *"Minimum allowed coverage: 89.0000%"* ]]
  [[ "$output" == *"FAIL: PR coverage (88.8%) is below the minimum allowed coverage (89.0000%)."* ]]
}

@test "coverage checker rejects invalid COVERAGE_TOLERANCE" {
  export COVERAGE_TOLERANCE="abc"

  run bash ./lib/code_coverage_checker.sh

  [[ "$status" -eq 1 ]]
  [[ "$output" == *"COVERAGE_TOLERANCE must be a non-negative numeric value"* ]]
}
