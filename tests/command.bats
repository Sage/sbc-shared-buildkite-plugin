#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

@test "runs BUILDKITE_COMMAND if set" {
  export BUILDKITE_LABEL="Test Command Step"
  export BUILDKITE_COMMAND="echo 'Hello, World!'"

  run ./hooks/command

  [[ "$status" -eq 0 ]]
  [[ "$output" == *"Hello, World!"* ]]
}

@test "does nothing if BUILDKITE_COMMAND is blank" {
  export BUILDKITE_COMMAND=""

  run ./hooks/command

  [[ "$status" -eq 0 ]]
  [[ "$output" == "" ]]
}
