#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

bats_require_minimum_version 1.5.0

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
}

teardown() {
  cd "$PLUGIN_ROOT"
}

set_up_push_param_fixture() {
  TEST_PLUGIN_DIR="$BATS_TEST_TMPDIR/plugin"

  mkdir -p "$TEST_PLUGIN_DIR/hooks" "$TEST_PLUGIN_DIR/lib" "$TEST_PLUGIN_DIR/configuration"
  cp "$PLUGIN_ROOT/hooks/post-command" "$TEST_PLUGIN_DIR/hooks/post-command"
  cp "$PLUGIN_ROOT/lib/functions.sh" "$TEST_PLUGIN_DIR/lib/functions.sh"
}

@test "complains if ACTION is not recognized" {
  export BUILDKITE_PLUGIN_SBC_SHARED_ACTION="not_a_real_action"

  run "$PLUGIN_ROOT/hooks/post-command"

  [[ "$status" -eq 1 ]]
  [[ "$output" == *"Unsupported action"* ]]
}

set_up_push_image_env_vars() {
  export ACCOUNT_ID="123"
  export APP="myapp"
  export DOCKER_TAG="mytag"
  export ENVIRONMENT="test"
  export BK_BRANCH="mybranch"
  export MULTIARCH_IMAGE_PUSH="false"
  export TARGET_TAG=""
  export BUILDKITE_PIPELINE_DEFAULT_BRANCH="main"
  export HAS_DB_IMAGE="true"
  export BUILDKITE_BUILD_NUMBER="123"
  export S1_REGION="made-up-region"
  export REPO="myrepo"
  export BK_ECR="123.buildkite.ecr.repo/myrepo"

  export BUILDKITE_PLUGIN_SBC_SHARED_ACTION="push_image"
}

@test "push_image action pulls, tags, and pushes the docker image" {
  set_up_push_image_env_vars

  stub docker "buildx imagetools create --tag 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch 123.buildkite.ecr.repo/myrepo:myapp-mytag-build-123 : echo pushing manifest"

  run -0 "$PLUGIN_ROOT/hooks/post-command"

  [[ "${lines[0]}" == *"--- :floppy_disk: Push test image for myapp"* ]]
  [[ "${lines[1]}" == *"Pushing image for myapp using tag: mybranch"* ]]
  [[ "${lines[2]}" == *"Creating manifest: 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch with 123.buildkite.ecr.repo/myrepo:myapp-mytag-build-123"* ]]
  [[ "${lines[3]}" == *"pushing manifest"* ]]

  unstub docker
}

@test "push_param action runs the configuration pusher with the config path and S1 region" {
  set_up_push_param_fixture
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'echo "working directory: $PWD"' \
    'echo "config path: $1"' \
    'echo "AWS region: $AWS_REGION"' \
    > "$TEST_PLUGIN_DIR/configuration/push.sh"
  chmod +x "$TEST_PLUGIN_DIR/configuration/push.sh"

  export BUILDKITE_PLUGIN_SBC_SHARED_ACTION="push_param"
  export ENVIRONMENT="test"
  export LANDSCAPE="blue"
  export S1_REGION="eu-west-2"

  original_directory="$PWD"
  cd "$TEST_PLUGIN_DIR"
  run -0 ./hooks/post-command
  cd "$original_directory"

  [[ "${lines[0]}" == "working directory: $TEST_PLUGIN_DIR/configuration" ]]
  [[ "${lines[1]}" == "config path: test/blue" ]]
  [[ "${lines[2]}" == "AWS region: eu-west-2" ]]
}

@test "push_param action returns the configuration pusher's failure status" {
  set_up_push_param_fixture
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'echo "configuration push failed"' \
    'exit 23' \
    > "$TEST_PLUGIN_DIR/configuration/push.sh"
  chmod +x "$TEST_PLUGIN_DIR/configuration/push.sh"

  export BUILDKITE_PLUGIN_SBC_SHARED_ACTION="push_param"
  export ENVIRONMENT="production"
  export LANDSCAPE="green"
  export S1_REGION="eu-west-1"

  original_directory="$PWD"
  cd "$TEST_PLUGIN_DIR"
  run ./hooks/post-command
  cd "$original_directory"

  [[ "$status" -eq 23 ]]
  [[ "$output" == "configuration push failed" ]]
}

@test "push_image with multiarch=true creates single manifest with both images" {
  set_up_push_image_env_vars
  export MULTIARCH_IMAGE_PUSH="true"

  stub docker "buildx imagetools create --tag 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch 123.buildkite.ecr.repo/myrepo:myapp-mytag-build-123 123.buildkite.ecr.repo/myrepo:myapp-mytag-arm64-build-123 : echo pushing multi-arch manifest"

  run -0 "$PLUGIN_ROOT/hooks/post-command"

  [[ "${lines[0]}" == *"--- :floppy_disk: Push test image for myapp"* ]]
  [[ "${lines[1]}" == *"Pushing image for myapp using tag: mybranch"* ]]
  [[ "${lines[2]}" == *"Creating multi-arch manifest: 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch with 123.buildkite.ecr.repo/myrepo:myapp-mytag-build-123 and 123.buildkite.ecr.repo/myrepo:myapp-mytag-arm64-build-123"* ]]
  [[ "${lines[3]}" == *"pushing multi-arch manifest"* ]]

  unstub docker
}

@test "push_image with env=qa addionally pushes test and database images" {
  set_up_push_image_env_vars
  export ENVIRONMENT="qa"

  stub docker "buildx imagetools create --tag 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch 123.buildkite.ecr.repo/myrepo:myapp-mytag-build-123 : echo pushing app manifest"
  stub docker "buildx imagetools create --tag 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:database-mybranch 123.buildkite.ecr.repo/myrepo:myapp-database-build-123 : echo pushing db manifest"

  run -0 "$PLUGIN_ROOT/hooks/post-command"

  [[ "$output" == *"pushing app manifest"* ]]
  [[ "$output" == *"DB image"* ]]
  [[ "$output" == *"pushing db manifest"* ]]

  unstub docker
}

@test "push_image does not attach VEX when vex_script is unset" {
  set_up_push_image_env_vars

  stub docker "buildx imagetools create --tag 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch 123.buildkite.ecr.repo/myrepo:myapp-mytag-build-123 : echo pushing manifest"

  run -0 "$PLUGIN_ROOT/hooks/post-command"

  [[ "$output" != *"Attach VEX attestation"* ]]

  unstub docker
}

@test "push_image attaches VEX with OCI referrer" {
  set_up_push_image_env_vars
  export VEX_SCRIPT="$PLUGIN_ROOT/tests/support/emit_vex.sh"
  export VEX_OUTPUT_FILE="$PLUGIN_ROOT/tests/support/generated.vex.json"

  echo '{"statements":[]}' > "$PLUGIN_ROOT/tests/support/generated.vex.json"

  stub docker "buildx imagetools create --tag 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch 123.buildkite.ecr.repo/myrepo:myapp-mytag-build-123 : echo pushing manifest"
  stub docker "scout --help : exit 0"
  stub docker "scout attestation add --file $PLUGIN_ROOT/tests/support/generated.vex.json --predicate-type https://openvex.dev/ns/v0.2.0 --referrer 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch : echo attaching vex"

  run -0 "$PLUGIN_ROOT/hooks/post-command"

  [[ "$output" == *"Attach VEX attestation to 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch"* ]]
  [[ "$output" == *"attaching vex"* ]]

  unstub docker
}
