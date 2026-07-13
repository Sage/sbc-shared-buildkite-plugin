#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

setup() {
  mkdir -p .buildkite
  echo "myapp" > .buildkite/.application

  export BUILDKITE=true
  export BUILDKITE_BRANCH="mybranch"
  export BUILDKITE_COMMIT="abc123"
  export AWS_REGION="us-east-1"
  stub docker 'buildx inspect buildx-builder : exit 0'
}

teardown() {
  [ -f .buildkite/.application ] && rm .buildkite/.application
  [ -f .buildkite/release.sh ] && rm .buildkite/release.sh
  [ -d .buildkite ] && rmdir .buildkite

  unstub docker
  unset BUILDKITE_BRANCH BUILDKITE_COMMIT AWS_REGION BUILDKITE_PLUGIN_SBC_SHARED_ACTION
}

@test "pre-command hook copies release.sh when ACTION is set" {
  [[ ! -f .buildkite/release.sh ]]

  export BUILDKITE_PLUGIN_SBC_SHARED_ACTION="publish_gem"
  run ./hooks/pre-command

  [[ -f .buildkite/release.sh ]]
}

@test "pre-command hook exports COVERAGE_TOLERANCE from plugin config" {
  export BUILDKITE_PLUGIN_SBC_SHARED_ACTION="publish_gem"
  export BUILDKITE_PLUGIN_SBC_SHARED_COVERAGE_TOLERANCE="1.25"

  run bash -c 'source ./hooks/pre-command; echo "${COVERAGE_TOLERANCE:-}"'

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"1.25"* ]]
}
