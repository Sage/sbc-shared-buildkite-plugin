#!/usr/bin/env bats

@test "Python unit tests pass" {
  run python3 -B -m unittest discover -s tests/unit

  [[ "$status" -eq 0 ]]
}
