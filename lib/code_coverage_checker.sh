#!/usr/bin/env bash
set -euo pipefail

BUILDKITE_API_TOKEN="${BUILDKITE_API_TOKEN:-}"
ORG="${ORG:-sage-group-plc}"
BUILDKITE_PIPELINE_SLUG="${BUILDKITE_PIPELINE_SLUG:-}"
BASE_BRANCH="${BUILDKITE_PIPELINE_DEFAULT_BRANCH:-master}"
BUILDKITE_BUILD_NUMBER="${BUILDKITE_BUILD_NUMBER:-}"

# Artifact paths to resolve from Buildkite artifacts API.
BASELINE_COVERAGE_ARTIFACT="${BASELINE_COVERAGE_ARTIFACT:-coverage/.last_run.json}"
CURRENT_COVERAGE_ARTIFACT="${CURRENT_COVERAGE_ARTIFACT:-coverage/.last_run.json}"

# Allowed reduction in coverage, measured in percentage points.
COVERAGE_TOLERANCE="${COVERAGE_TOLERANCE:-0.00}"

# Local files written by this script.
BASELINE_ARTIFACTS_JSON="${BASELINE_ARTIFACTS_JSON:-base_artifacts.json}"
BASELINE_COVERAGE_FILE="${BASELINE_COVERAGE_FILE:-base-coverage-metrics.json}"
CURRENT_ARTIFACTS_JSON="${CURRENT_ARTIFACTS_JSON:-patch_artifacts.json}"
CURRENT_COVERAGE_FILE="${CURRENT_COVERAGE_FILE:-current-coverage-metrics.json}"

annotate_coverage_gate() {
  local style="$1"
  local message="$2"

  if command -v buildkite-agent >/dev/null 2>&1; then
    buildkite-agent annotate \
      --style "$style" \
      --context "coverage-gate" \
      "$message" || true
  fi
}

if [[ -z "$BUILDKITE_API_TOKEN" ]]; then
  echo "BUILDKITE_API_TOKEN is not set in this step environment." >&2
  exit 1
fi

if [[ -z "$BUILDKITE_PIPELINE_SLUG" ]]; then
  echo "BUILDKITE_PIPELINE_SLUG must be set to resolve Buildkite artifacts." >&2
  exit 1
fi

if [[ -z "$BUILDKITE_BUILD_NUMBER" ]]; then
  echo "BUILDKITE_BUILD_NUMBER must be set to resolve current build artifacts." >&2
  exit 1
fi

if ! awk \
  -v tolerance="$COVERAGE_TOLERANCE" \
  'BEGIN { exit !(tolerance ~ /^[0-9]+([.][0-9]+)?$/) }'
then
  echo "COVERAGE_TOLERANCE must be a non-negative numeric value (e.g. 0, 0.25, 1.5)." >&2
  exit 1
fi

buildkite_api_get() {
  local path="$1"

  curl -sS \
    -H "Authorization: Bearer $BUILDKITE_API_TOKEN" \
    "https://api.buildkite.com/v2/organizations/$ORG/pipelines/$BUILDKITE_PIPELINE_SLUG/$path"
}

latest_passed_build_id() {
  local branch="$1"
  local api_response
  local build_id

  api_response="$(
    buildkite_api_get \
      "builds?branch=$branch&state=passed&page=1&per_page=100"
  )"

  if [[ -z "$api_response" ]]; then
    echo "API returned empty response for branch: $branch" >&2
    return 1
  fi

  build_id="$(
    echo "$api_response" \
      | grep -oE '"number"[[:space:]]*:[[:space:]]*[0-9]+' \
      | head -1 \
      | grep -oE '[0-9]+' \
      || true
  )"

  if [[ -z "$build_id" ]]; then
    echo "No passed builds found for branch: $branch" >&2
    echo "API response: $api_response" >&2
    return 1
  fi

  echo "$build_id"
}

find_artifact_download_url() {
  local build_id="$1"
  local artifact_path="$2"
  local artifacts_file="$3"
  local page=0
  local download_url=""

  while :; do
    page=$((page + 1))

    buildkite_api_get \
      "builds/$build_id/artifacts?page=$page&per_page=100" \
      > "$artifacts_file"

    # Stop iterating when the API returns an empty page.
    if ! grep -q '"id"' "$artifacts_file"; then
      break
    fi

    download_url="$(
      tr -d '\n' < "$artifacts_file" \
        | sed 's/},{/},\
{/g' \
        | grep -F "\"path\":\"$artifact_path\"" \
        | sed -n 's/.*"download_url":"\([^"]*\)".*/\1/p' \
        | head -1 \
        || true
    )"

    if [[ -n "$download_url" ]]; then
      echo "$download_url"
      return 0
    fi
  done

  return 1
}

download_coverage_metrics() {
  local build_id="$1"
  local artifact_path="$2"
  local artifacts_file="$3"
  local output_file="$4"
  local label="$5"
  local download_url=""

  download_url="$(
    find_artifact_download_url \
      "$build_id" \
      "$artifact_path" \
      "$artifacts_file" \
      || true
  )"

  echo "$label download URL: $download_url"

  if [[ -z "$download_url" ]]; then
    local message

    message="Coverage gate skipped: $label artifact '$artifact_path' is not available for build $build_id. Coverage comparison was not performed."

    echo "Artifact path '$artifact_path' was not found for build $build_id." >&2
    annotate_coverage_gate "warning" "$message"
    exit 0
  fi

  curl -sS -L \
    -H "Authorization: Bearer $BUILDKITE_API_TOKEN" \
    "$download_url" \
    -o "$output_file"
}

extract_line_coverage() {
  local file="$1"

  sed -n \
    's/.*"line":[[:space:]]*\([0-9.][0-9.]*\).*/\1/p' \
    "$file" \
    | head -1
}

BASE_BUILD_ID="${BASE_BUILD_ID:-$(latest_passed_build_id "$BASE_BRANCH")}"

if [[ -z "$BASE_BUILD_ID" ]]; then
  echo "Could not resolve BASE_BUILD_ID from Buildkite API response for branch '$BASE_BRANCH'." >&2
  exit 1
fi

echo "Resolved BASE_BUILD_ID: $BASE_BUILD_ID"

download_coverage_metrics \
  "$BASE_BUILD_ID" \
  "$BASELINE_COVERAGE_ARTIFACT" \
  "$BASELINE_ARTIFACTS_JSON" \
  "$BASELINE_COVERAGE_FILE" \
  "Baseline"

download_coverage_metrics \
  "$BUILDKITE_BUILD_NUMBER" \
  "$CURRENT_COVERAGE_ARTIFACT" \
  "$CURRENT_ARTIFACTS_JSON" \
  "$CURRENT_COVERAGE_FILE" \
  "Current"

baseline_coverage="$(extract_line_coverage "$BASELINE_COVERAGE_FILE")"
current_coverage="$(extract_line_coverage "$CURRENT_COVERAGE_FILE")"

if [[ -z "$baseline_coverage" || -z "$current_coverage" ]]; then
  echo "Unable to parse coverage values from baseline/current JSON files." >&2
  exit 1
fi

echo "Downloaded baseline coverage: ${baseline_coverage}%"
echo "Current coverage: ${current_coverage}%"

coverage_baseline_label="${BASE_BRANCH} baseline"

# If COVERAGE is set, use it as the threshold instead of the downloaded
# baseline coverage.
if [[ -n "${COVERAGE:-}" ]]; then
  echo "Using COVERAGE threshold: ${COVERAGE}%"
  baseline_coverage="$COVERAGE"
  coverage_baseline_label="configured COVERAGE threshold"
fi

minimum_allowed_coverage="$(
  awk \
    -v baseline="$baseline_coverage" \
    -v tolerance="$COVERAGE_TOLERANCE" \
    'BEGIN {
      minimum = baseline - tolerance

      if (minimum < 0) {
        minimum = 0
      }

      printf "%.4f", minimum
    }'
)"

echo "Active baseline: ${baseline_coverage}% (${coverage_baseline_label})"
echo "Coverage tolerance: ${COVERAGE_TOLERANCE}%"
echo "Minimum allowed coverage: ${minimum_allowed_coverage}%"

if awk \
  -v current="$current_coverage" \
  -v minimum="$minimum_allowed_coverage" \
  'BEGIN { exit !(current + 0 < minimum + 0) }'
then
  message="Coverage regression failed: PR=${current_coverage}% baseline=${baseline_coverage}% tolerance=${COVERAGE_TOLERANCE}% minimum=${minimum_allowed_coverage}% source=${coverage_baseline_label}."

  echo "FAIL: PR coverage (${current_coverage}%) is below the minimum allowed coverage (${minimum_allowed_coverage}%)."
  annotate_coverage_gate "error" "$message"
  exit 1
fi

message="Coverage regression passed: PR=${current_coverage}% baseline=${baseline_coverage}% tolerance=${COVERAGE_TOLERANCE}% minimum=${minimum_allowed_coverage}% source=${coverage_baseline_label}."

echo "OK: PR coverage (${current_coverage}%) is within tolerance of the ${coverage_baseline_label} (${baseline_coverage}%)."
annotate_coverage_gate "success" "$message"
