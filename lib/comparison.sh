#!/usr/bin/env bash
set -euo pipefail

annotate_coverage_gate() {
  local style="$1"
  local message="$2"

  if command -v buildkite-agent >/dev/null 2>&1; then
    buildkite-agent annotate --style "$style" --context "coverage-gate" "$message" || true
  fi
}

if [[ -z "${BUILDKITE_API_TOKEN:-}" ]]; then
  echo "BUILDKITE_API_TOKEN is not set in this step environment." >&2
  echo "The docker-compose plugin 'env: [BUILDKITE_API_TOKEN]' only forwards existing vars from the agent." >&2
  exit 1
fi

ORG="sage-group-plc"
PIPELINE="sage_one_advanced"
export ARTIFACT_PATH="master-coverage/.last_run.json"

# 1) Get latest passed build on master
BUILD_ID=$(
  curl -sS -H "Authorization: Bearer $BUILDKITE_API_TOKEN" \
    "https://api.buildkite.com/v2/organizations/$ORG/pipelines/$PIPELINE/builds?branch=master&state=passed&per_page=1" \
  | ruby -rjson -e 'puts JSON.parse(STDIN.read).last["number"]'
)
echo $BUILD_ID

# 2) List artifacts for that build and find the one you want
curl -sS -H "Authorization: Bearer $BUILDKITE_API_TOKEN" \
  "https://api.buildkite.com/v2/organizations/$ORG/pipelines/$PIPELINE/builds/$BUILD_ID/artifacts?page=3&per_page=100" \
  -o artifacts.json

DOWNLOAD_URL=$(ruby -rjson -e '
  artifacts = JSON.parse(File.read(File.join(Dir.pwd, "artifacts.json")))
  a = artifacts.find { |x| x["path"] == ENV.fetch("ARTIFACT_PATH") }
  puts(a ? a["download_url"] : "")
' ARTIFACT_PATH="$ARTIFACT_PATH")


if [[ -z "$DOWNLOAD_URL" ]]; then
  echo "Artifact path '$ARTIFACT_PATH' was not found for build $BUILD_ID." >&2
  annotate_coverage_gate "warning" "Coverage gate skipped: artifact '$ARTIFACT_PATH' is not available for build $BUILD_ID.
                                    Coverage comparison was not performed."
  exit 0
fi

# 3) Download artifact
curl -sS -L -H "Authorization: Bearer $BUILDKITE_API_TOKEN" \
  "$DOWNLOAD_URL" -o coverage-baseline.json

echo "$DOWNLOAD_URL"

buildkite-agent artifact download "coverage/.last_run.json" .

baseline_coverage=$(ruby -rjson -e 'puts JSON.parse(File.read("coverage-baseline.json"))["result"]["line"]')
current_coverage=$(ruby -rjson -e 'puts JSON.parse(File.read("coverage/.last_run.json"))["result"]["line"]')

echo "Baseline coverage: ${baseline_coverage}%"
echo "Current coverage: ${current_coverage}%"

if ruby -e 'current = Float(ARGV[0]); baseline = Float(ARGV[1]); exit(current < baseline ? 0 : 1)' "$current_coverage" "$baseline_coverage"; then
  echo "FAIL: PR coverage (${current_coverage}%) is below master baseline (${baseline_coverage}%)."
  annotate_coverage_gate "error" "Coverage gate failed: PR coverage (${current_coverage}%) is below master baseline (${baseline_coverage}%)."
  exit 1
fi

echo "OK: PR coverage is >= master baseline."
annotate_coverage_gate "success" "Coverage gate passed: PR coverage (${current_coverage}%) is greater than or equal to master baseline (${baseline_coverage}%)."
