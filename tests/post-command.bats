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

  stub docker "run --rm -v /root/.docker:/root/.docker:ro -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION -e AWS_DEFAULT_REGION -e AWS_PROFILE ghcr.io/oras-project/oras:v1.3.3 cp -r --from-distribution-spec v1.1-referrers-api --to-distribution-spec v1.1-referrers-api 123.buildkite.ecr.repo/myrepo:myapp-mytag-build-123 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch-x86_64 : echo copying app x86_64"
  stub docker "run --rm -v /root/.docker:/root/.docker:ro -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION -e AWS_DEFAULT_REGION -e AWS_PROFILE ghcr.io/oras-project/oras:v1.3.3 manifest index create 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch-x86_64 : echo pushing manifest"

  run -0 ./hooks/post-command

  [[ "${lines[0]}" == *"--- :floppy_disk: Push test image for myapp"* ]]
  [[ "${lines[1]}" == *"Pushing image for myapp using tag: mybranch"* ]]
  [[ "$output" == *"Copying image and referrers: 123.buildkite.ecr.repo/myrepo:myapp-mytag-build-123 -> 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch-x86_64"* ]]
  [[ "$output" == *"copying app x86_64"* ]]
  [[ "$output" == *"Creating and pushing manifest: 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch with 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch-x86_64"* ]]
  [[ "$output" == *"pushing manifest"* ]]

  unstub docker
}

@test "push_image with env=qa addionally pushes test and database images" {
  set_up_push_image_env_vars
  export ENVIRONMENT="qa"

  stub docker "run --rm -v /root/.docker:/root/.docker:ro -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION -e AWS_DEFAULT_REGION -e AWS_PROFILE ghcr.io/oras-project/oras:v1.3.3 cp -r --from-distribution-spec v1.1-referrers-api --to-distribution-spec v1.1-referrers-api 123.buildkite.ecr.repo/myrepo:myapp-mytag-build-123 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch-x86_64 : echo copying app x86_64"
  stub docker "run --rm -v /root/.docker:/root/.docker:ro -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION -e AWS_DEFAULT_REGION -e AWS_PROFILE ghcr.io/oras-project/oras:v1.3.3 manifest index create 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch-x86_64 : echo pushing app manifest"
  stub docker "run --rm -v /root/.docker:/root/.docker:ro -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION -e AWS_DEFAULT_REGION -e AWS_PROFILE ghcr.io/oras-project/oras:v1.3.3 cp -r --from-distribution-spec v1.1-referrers-api --to-distribution-spec v1.1-referrers-api 123.buildkite.ecr.repo/myrepo:myapp-database-build-123 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:database-mybranch-x86_64 : echo copying db x86_64"
  stub docker "run --rm -v /root/.docker:/root/.docker:ro -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION -e AWS_DEFAULT_REGION -e AWS_PROFILE ghcr.io/oras-project/oras:v1.3.3 manifest index create 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:database-mybranch 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:database-mybranch-x86_64 : echo pushing db manifest"

  run -0 ./hooks/post-command

  [[ "$output" == *"copying app x86_64"* ]]
  [[ "$output" == *"pushing app manifest"* ]]
  [[ "$output" == *"DB image"* ]]
  [[ "$output" == *"copying db x86_64"* ]]
  [[ "$output" == *"pushing db manifest"* ]]

  unstub docker
}

@test "push_image with multiarch=true copies both architectures and creates one manifest" {
  set_up_push_image_env_vars
  export MULTIARCH_IMAGE_PUSH="true"

  stub docker "run --rm -v /root/.docker:/root/.docker:ro -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION -e AWS_DEFAULT_REGION -e AWS_PROFILE ghcr.io/oras-project/oras:v1.3.3 cp -r --from-distribution-spec v1.1-referrers-api --to-distribution-spec v1.1-referrers-api 123.buildkite.ecr.repo/myrepo:myapp-mytag-build-123 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch-x86_64 : echo copying app x86_64"
  stub docker "run --rm -v /root/.docker:/root/.docker:ro -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION -e AWS_DEFAULT_REGION -e AWS_PROFILE ghcr.io/oras-project/oras:v1.3.3 cp -r --from-distribution-spec v1.1-referrers-api --to-distribution-spec v1.1-referrers-api 123.buildkite.ecr.repo/myrepo:myapp-mytag-arm64-build-123 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch-arm64 : echo copying app arm64"
  stub docker "run --rm -v /root/.docker:/root/.docker:ro -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION -e AWS_DEFAULT_REGION -e AWS_PROFILE ghcr.io/oras-project/oras:v1.3.3 manifest index create 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch-x86_64 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch-arm64 : echo pushing multiarch manifest"

  run -0 ./hooks/post-command

  [[ "$output" == *"copying app x86_64"* ]]
  [[ "$output" == *"copying app arm64"* ]]
  [[ "$output" == *"Creating and pushing manifest: 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch with 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch-x86_64 and 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch-arm64"* ]]
  [[ "$output" == *"pushing multiarch manifest"* ]]

  unstub docker
}

@test "push_image fails when containerized oras operations fail" {
  set_up_push_image_env_vars
  stub docker "run --rm -v /root/.docker:/root/.docker:ro -e AWS_ACCESS_KEY_ID -e AWS_SECRET_ACCESS_KEY -e AWS_SESSION_TOKEN -e AWS_REGION -e AWS_DEFAULT_REGION -e AWS_PROFILE ghcr.io/oras-project/oras:v1.3.3 cp -r --from-distribution-spec v1.1-referrers-api --to-distribution-spec v1.1-referrers-api 123.buildkite.ecr.repo/myrepo:myapp-mytag-build-123 123.dkr.ecr.made-up-region.amazonaws.com/myrepo:mybranch-x86_64 : exit 1"

  run ./hooks/post-command

  [[ "$status" -eq 1 ]]

  unstub docker
}
