#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

bats_require_minimum_version 1.5.0

setup() {
  mkdir -p .buildkite
  echo "myapp" > .buildkite/.application

  export BUILDKITE=true
  export BUILDKITE_BRANCH="mybranch"
  export BUILDKITE_COMMIT="abc123"
  export AWS_REGION="us-east-1"
}

teardown() {
  [ -f .buildkite/.application ] && rm .buildkite/.application
  [ -d .buildkite ] && rmdir .buildkite
}

@test "complains if ACTION is not recognized" {
  export BUILDKITE_PLUGIN_SBC_SHARED_ACTION="not_a_real_action"

  run ./hooks/post-command

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

  stub docker "pull 123.buildkite.ecr.repo/myrepo:myapp-mytag-build-123 --platform linux/amd64 : echo pulling"
  stub docker "tag 123.buildkite.ecr.repo/myrepo:myapp-mytag-build-123 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch : echo tagging"
  stub docker "push 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch : echo pushing"

  run -0 ./hooks/post-command

  [[ "${lines[0]}" == *"--- :floppy_disk: Push test image for myapp"* ]]
  [[ "${lines[1]}" == *"Pushing image for myapp using tag: mybranch"* ]]
  [[ "${lines[2]}" == *"Pushing"* ]]
  [[ "${lines[3]}" == *"pulling"* ]]
  [[ "${lines[4]}" == *"tagging"* ]]
  [[ "${lines[5]}" == *"pushing"* ]]

  unstub docker
}

@test "push_image with env=qa addionally pushes test and database images" {
  set_up_push_image_env_vars
  export ENVIRONMENT="qa"

  stub docker "pull 123.buildkite.ecr.repo/myrepo:myapp-mytag-build-123 --platform linux/amd64 : echo pulling app image"
  stub docker "tag 123.buildkite.ecr.repo/myrepo:myapp-mytag-build-123 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch : echo tagging"
  stub docker "push 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch : echo pushing"
  stub docker "pull 123.buildkite.ecr.repo/myrepo:myapp-database-build-123 --platform linux/amd64 : echo pulling db image"
  stub docker "tag 123.buildkite.ecr.repo/myrepo:myapp-database-build-123 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:database-mybranch : echo tagging db image"
  stub docker "push 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:database-mybranch : echo pushing db image"

  run -0 ./hooks/post-command

  unstub docker
}
