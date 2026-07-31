#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

setup() {
  export PLUGIN_ROOT="$BATS_TEST_DIRNAME/.."
  export TEST_WORKING_DIR="$BATS_TEST_TMPDIR/workspace"

  source "$PLUGIN_ROOT/lib/functions.sh"

  mkdir -p "$TEST_WORKING_DIR"
  cd "$TEST_WORKING_DIR"
  mkdir -p .buildkite
  echo "myapp" > .buildkite/.application
}

teardown() {
  cd "$PLUGIN_ROOT"
}

@test "setup() requires at least one argument" {
  run setup
  [ "$status" -eq 1 ]
  [[ "$output" == *"Please define a repo prefix name"* ]]
}

@test "setup() exports a bunch of environment variables" {
  export BUILDKITE_BRANCH="mybranch"
  export BUILDKITE_COMMIT="abc123"

  stub docker 'buildx inspect buildx-builder : exit 0'

  setup myprefix

  [[ "$APP" = "myapp" ]]
  [[ "$REPO" = "myprefix/myapp" ]]
  [[ "$BK_BRANCH" = "mybranch" ]]
  [[ "$CI_BRANCH" = "mybranch" ]]
  [[ "$CI_COMMIT" = "$BUILDKITE_COMMIT" ]]
  [[ "$BK_ECR" = *268539851198.dkr.ecr* ]]
  [[ "$BK_CACHE" = *268539851198.dkr.ecr* ]]

  unstub docker
}
