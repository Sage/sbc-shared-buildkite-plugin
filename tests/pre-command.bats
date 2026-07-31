#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

setup() {
  export PLUGIN_ROOT="$BATS_TEST_DIRNAME/.."
  export TEST_WORKING_DIR="$BATS_TEST_TMPDIR/workspace"

  mkdir -p "$TEST_WORKING_DIR"
  cd "$TEST_WORKING_DIR"
  mkdir -p .buildkite
  echo "myapp" > .buildkite/.application

  export BUILDKITE=true
  export BUILDKITE_BRANCH="mybranch"
  export BUILDKITE_COMMIT="abc123"
  export AWS_REGION="us-east-1"
  stub docker 'buildx inspect buildx-builder : exit 0'
}

teardown() {
  unstub docker
  unset BUILDKITE_BRANCH BUILDKITE_COMMIT AWS_REGION BUILDKITE_PLUGIN_SBC_SHARED_ACTION
  cd "$PLUGIN_ROOT"
}

@test "pre-command hook copies release.sh when ACTION is set" {
  [[ ! -f .buildkite/release.sh ]]

  export BUILDKITE_PLUGIN_SBC_SHARED_ACTION="publish_gem"
  run "$PLUGIN_ROOT/hooks/pre-command"

  [[ -f .buildkite/release.sh ]]
}

@test "pre-command hook exports COVERAGE_TOLERANCE from plugin config" {
  export BUILDKITE_PLUGIN_SBC_SHARED_ACTION="publish_gem"
  export BUILDKITE_PLUGIN_SBC_SHARED_COVERAGE_TOLERANCE="1.25"

  run bash -c 'source "$PLUGIN_ROOT/hooks/pre-command"; echo "${COVERAGE_TOLERANCE:-}"'

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"1.25"* ]]
}
