#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

setup() {
  source lib/functions.sh
}

@test "varx should not error if all variables are set" {
  export FOO=bar
  run varx FOO
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "varx should error if a variable is not set" {
  run varx FOO
  [ "$status" -eq 1 ]
  [[ "$output" == *"FOO is not set"* ]]
}
