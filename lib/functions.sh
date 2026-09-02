varx () {
  for var_name in "$@"; do
    if [[ -z "${!var_name}" ]]; then
      echo "$var_name is not set."
      exit 1
    fi
  done
}

setup() {
  if [ -z $1 ]; then
    echo "Please define a repo prefix name (e.g. setup sageone)"
    exit 1
  fi

  # Setup the env that contains the application name and repo name
  export APP=$(cat .buildkite/.application)
  export REPO=$1/$APP

  # Setup the proper docker tag to be used depending on GH tag and/or branch.
  #
  # Note that merge queues may use a branch name such as
  # gh-readonly-queue/master/pr-1302-7f6d0543067187068f04eefcb7c3edd3b0e7e3ab
  # so we can use the basename of such branches.
  branch_name=$(basename $BUILDKITE_BRANCH)
  export BK_BRANCH="${branch_name:-$BUILDKITE_TAG}"

  # Setup CI branch and time used by various other tools. E.g. ssm pusher
  export CI_STRING_TIME=$(date '+%Y-%m-%d %H:%M:%S')
  export CI_BRANCH=$BK_BRANCH
  export CI_COMMIT=$BUILDKITE_COMMIT

  # Change the output of the docker build process to not be truncated in BK
  if [[ "$BUILDKITE" == "true" ]]; then
    export BUILDKIT_PROGRESS=plain
  fi

  export BK_ECR=268539851198.dkr.ecr.$AWS_REGION.amazonaws.com/sageone/buildkite
  export BK_CACHE=268539851198.dkr.ecr.$AWS_REGION.amazonaws.com/sageone/cache

  # Needed for --cache-from and --cache-to
  local builder_name=buildx-builder
  if ! docker buildx inspect $builder_name > /dev/null 2>&1; then
    docker buildx create --driver docker-container --name $builder_name --use --bootstrap
  fi
}

# convert --<switch> to a variable
switches() {
  while [ $# -gt 0 ]; do
    if [[ $1 == "--"* ]]; then
      v="${1/--/}"
      export $v="$2"
    fi
    shift
  done
}

# validate list of switch names exist as a set variable
validate_switches() {
  arr=("$@")

  set +u
  for item in "${arr[@]}"
  do
    if [ -z "${!item}" ]; then
      echo "--$item is not set"
      echo $@
      set -u
      exit 1
    fi
  done
  set -u
}

# target   => (Optional) set the target build stage to build
# tag      => variant of the docker image e.g. app or database
# file     => source Dockerfile
# cache_id => typically the git branch name
# push     => (Optional) "true" to push to the registry WITH attestations
#             (provenance + SBOM). When unset we --load into the local daemon
#             (used for the test image), which cannot carry attestations.
buildx() {
  local target=
  local push=

  switches "$@"
  validate_switches tag file cache_id
  varx REPO BUILDKITE_PIPELINE_DEFAULT_BRANCH BUILDKITE_BUILD_NUMBER

  echo "+++ :building_construction: Build $tag"

  local OPTIONAL_TARGET=
  if [[ -n $target ]]; then
    OPTIONAL_TARGET="--target $target"
  fi

  # Output + attestation strategy.
  #
  # --load routes through the classic docker image store, which cannot hold
  # attestations (BuildKit silently drops them). So attestations only make
  # sense on the --push path. For images we ship (and scan with Docker Scout)
  # we push WITH:
  #   --provenance=mode=max  records the full build graph + layer->step mapping
  #                          so Scout can identify the DHI base image and split
  #                          base-image CVEs from our app-layer CVEs.
  #   --sbom=true            emits an SBOM attestation: exact package inventory
  #                          and lets DHI's VEX / "not-affected" data apply.
  local OUTPUT_ARGS=(--load)
  if [[ $push == "true" ]]; then
    OUTPUT_ARGS=(--push --provenance=mode=max --sbom=true)
  fi

  local BUILD_IMAGE_NAME=$BK_ECR:$APP-$tag-build-$BUILDKITE_BUILD_NUMBER

  echo "--- :docker: Building $tag as $BUILD_IMAGE_NAME with build args: $OPTIONAL_TARGET ${OUTPUT_ARGS[@]}"

  docker buildx build \
    --file $file \
    --pull \
    --build-arg CI_BRANCH \
    --build-arg CI_STRING_TIME \
    --build-arg CI_COMMIT \
    --build-arg CACHEBUST=$(date +%Y-%m-%d) \
    --cache-to mode=max,image-manifest=true,oci-mediatypes=true,type=registry,ref=$BK_CACHE:$APP-$tag-$cache_id \
    --cache-from $BK_CACHE:$APP-$tag-$cache_id \
    --cache-from $BK_CACHE:$APP-$tag-$BUILDKITE_PIPELINE_DEFAULT_BRANCH \
    --secret id=railslts,env=BUNDLE_GEMS__RAILSLTS__COM \
    --secret id=jfrog,env=BUNDLE_SAGEONEGEMS__JFROG__IO \
    --secret id=jfrog_npm,env=SAGEONEGEMS_JFROG_NPM_TOKEN \
    --secret id=jfrog_nuget,env=NUGET_JFROG_PASSWORD \
    --ssh default \
    $OPTIONAL_TARGET \
    "${OUTPUT_ARGS[@]}" \
    --tag $BUILD_IMAGE_NAME \
    .
}

# Push an image into the BK ECR
pushx () {
  switches "$@"
  validate_switches app tag
  varx REPO BUILDKITE_BUILD_NUMBER

  local BUILD_IMAGE_NAME=$BK_ECR:$app-$tag-build-$BUILDKITE_BUILD_NUMBER

  echo "--- :floppy_disk: Push $tag as $BUILD_IMAGE_NAME"

  docker push $BUILD_IMAGE_NAME
}

# Push an image into a target ECR for deployment
# Variables used:
# account_id: AWS account id which the image will be pushed to. Used to construct the final ECR address.
# app: Application name e.g. 'sage_one_advanced'. Used to find the source image in the Buildkite ECR.
# tag: Image variant e.g 'application', 'test' or 'database'.
# multiarch: Whether to push a manifest with images for both amd64 and arm64 architectures.
# BUILDKITE_BUILD_NUMBER: Used to find the source image in the Buildkite ECR.
# S1_REGION: AWS region of the target ECR.
# BK_BRANCH: The git branch or tag being built, used to determine the target docker image tag in the target ECR, unless that is overridden by TARGET_TAG.
push_image () {
  switches "$@"
  validate_switches account_id app tag multiarch
  varx BUILDKITE_BUILD_NUMBER S1_REGION BK_BRANCH

  # If the override ENV option was specified in the pipeline, use that tag value.
  # This supports custom tags like `last-successful-build` that don't match the GH tag/branch that triggered the commit
  local target_tag=${TARGET_TAG:-$BK_BRANCH}

  echo "Pushing image for $app using tag: $target_tag"

  TARGET_ECR=$account_id.dkr.ecr.$S1_REGION.amazonaws.com/$REPO:$target_tag

  SOURCE_IMAGE_X86_64=$BK_ECR:$app-$tag-build-$BUILDKITE_BUILD_NUMBER

  if [[ "$multiarch" == "true" ]]; then
    SOURCE_IMAGE_ARM64=$BK_ECR:$app-$tag-arm64-build-$BUILDKITE_BUILD_NUMBER

    echo "Creating multi-arch manifest: $TARGET_ECR with $SOURCE_IMAGE_X86_64 and $SOURCE_IMAGE_ARM64"

    docker buildx imagetools create --tag $TARGET_ECR $SOURCE_IMAGE_X86_64 $SOURCE_IMAGE_ARM64
  else
    echo "Creating manifest: $TARGET_ECR with $SOURCE_IMAGE_X86_64"

    docker buildx imagetools create --tag $TARGET_ECR $SOURCE_IMAGE_X86_64
  fi
}

attach_vex_attestation() {
  local image_ref=$1
  local vex_script=${VEX_SCRIPT:-}

  [ -n "$vex_script" ] || return 0

  export DOCKER_SCOUT_HUB_USER=sage
  export DOCKER_SCOUT_HUB_PASSWORD="${DOCKER_HUB_API_KEY:-}"
  export HOME="${HOME:-/var/lib/buildkite-agent}"
  export DOCKER_CONFIG="${DOCKER_CONFIG:-$HOME/.docker}"
  export DOCKER_HOME="$DOCKER_CONFIG"
  export PATH="/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin:$PATH"
  mkdir -p "$DOCKER_CONFIG/cli-plugins"

  echo "--- :docker: Docker Scout environment diagnostics"
  echo "user=$(id -un 2>/dev/null || echo unknown) uid=$(id -u 2>/dev/null || echo unknown)"
  echo "HOME=$HOME"
  echo "DOCKER_CONFIG=$DOCKER_CONFIG"
  echo "DOCKER_HOME=$DOCKER_HOME"
  echo "PATH=$PATH"
  echo "SHELL=${SHELL:-unset}"
  echo "PWD=$PWD"
  echo "BUILDKITE_BUILD_CHECKOUT_PATH=${BUILDKITE_BUILD_CHECKOUT_PATH:-unset}"

  local docker_bin
  docker_bin="$(command -v docker 2>/dev/null || true)"
  echo "docker command path=${docker_bin:-not found}"

  if [[ -z "$docker_bin" ]] || [[ ! -x "$docker_bin" ]]; then
    echo "Docker candidates in standard locations:"
    for docker_candidate in /usr/local/bin/docker /usr/bin/docker /bin/docker /snap/bin/docker; do
      if [[ -e "$docker_candidate" ]]; then
        ls -l "$docker_candidate" 2>&1 || true
      fi
    done
    echo "Docker CLI is not installed on this agent; cannot install Docker Scout or attach VEX attestations." >&2
    return 1
  fi

  echo "Docker executable metadata:"
  ls -l "$docker_bin" 2>&1 || true
  echo "docker resolved path=$(readlink -f "$docker_bin" 2>/dev/null || echo unavailable)"
  export PATH="$(dirname "$docker_bin"):$PATH"

  local docker_version
  local docker_version_status
  if docker_version=$("$docker_bin" --version 2>&1); then
    docker_version_status=0
  else
    docker_version_status=$?
  fi
  echo "docker --version status=$docker_version_status output=${docker_version:-empty}"

  if [[ "$docker_version_status" -ne 0 ]]; then
    echo "Docker CLI is not available on this agent; cannot install Docker Scout or attach VEX attestations." >&2
    return 1
  fi

  local checkout_path=${BUILDKITE_BUILD_CHECKOUT_PATH:-$PWD}
  local vex_script_path

  vex_script_path=$vex_script
  if [[ "$vex_script_path" != /* ]]; then
    vex_script_path="$checkout_path/$vex_script_path"
  fi

  if [ ! -f "$vex_script_path" ]; then
    echo "VEX script not found: $vex_script_path" >&2
    return 1
  fi

  local scout_plugin="$DOCKER_CONFIG/cli-plugins/docker-scout"
  echo "Docker Scout installation directories:"
  for scout_directory in "$HOME/.docker" "$DOCKER_CONFIG" "$DOCKER_CONFIG/cli-plugins"; do
    if [[ -e "$scout_directory" ]]; then
      ls -ld "$scout_directory" 2>&1 || true
    else
      echo "$scout_directory does not exist"
    fi
  done

  if [[ -e "$scout_plugin" ]]; then
    ls -l "$scout_plugin" 2>&1 || true
  else
    echo "$scout_plugin does not exist"
  fi

  if [[ ! -x "$scout_plugin" ]]; then
    echo "--- :docker: Installing Docker Scout CLI plugin"
    local scout_install_status
    if HOME="$HOME" DOCKER_CONFIG="$DOCKER_CONFIG" DOCKER_HOME="$DOCKER_HOME" PATH="$PATH" \
      sh -c 'curl -fsSL https://raw.githubusercontent.com/docker/scout-cli/main/install.sh | sh -s -- -d'; then
      scout_install_status=0
    else
      scout_install_status=$?
    fi
    echo "Docker Scout installer status=$scout_install_status"

    if [[ -e "$scout_plugin" ]]; then
      ls -l "$scout_plugin" 2>&1 || true
    else
      echo "$scout_plugin was not created"
    fi
  fi

  local scout_version
  local scout_version_status
  if scout_version=$("$docker_bin" scout version 2>&1); then
    scout_version_status=0
  else
    scout_version_status=$?
  fi
  echo "docker scout version status=$scout_version_status output=${scout_version:-empty}"

  if [[ "$scout_version_status" -ne 0 ]]; then
    echo "Docker Scout CLI is not available on this agent; install the scout plugin before attaching VEX attestations." >&2
    return 1
  fi

  local vex_file
  vex_file=$(
    cd "$checkout_path"
    "$vex_script_path" "$image_ref"
  )

  if [ -n "$BUILDKITE" ] && command -v buildkite-agent >/dev/null 2>&1; then
    echo "--- :artifacts: Upload VEX attestation"
    buildkite-agent artifact upload "$vex_file"
  fi

  echo "--- :mag: Attach VEX attestation to $image_ref"

  local docker_config_dir="${DOCKER_CONFIG:-$HOME/.docker}"
  mkdir -p "$docker_config_dir"

  local ecr_registry="${image_ref%%/*}"
  local ecr_region="${ecr_registry#*.dkr.ecr.}"
  ecr_region="${ecr_region%.amazonaws.com}"

  if [[ "$ecr_registry" == *.dkr.ecr.*.amazonaws.com ]] && command -v aws >/dev/null 2>&1; then
    echo "--- :aws: Re-authenticating Docker for $ecr_registry"
    DOCKER_CONFIG="$docker_config_dir" aws ecr get-login-password --region "$ecr_region" | \
      DOCKER_CONFIG="$docker_config_dir" "$docker_bin" login --username AWS --password-stdin "$ecr_registry" >/dev/null
  fi

  DOCKER_CONFIG="$docker_config_dir" "$docker_bin" scout attestation add \
    --file "$vex_file" \
    --predicate-type "https://openvex.dev/ns/v0.2.0" \
    --org "sage" \
    --referrer "$image_ref"

  rm -f "$vex_file"
}

compare_coverage_metrics() {
  switches "$@"

  # Optional override: if --coverage was provided, propagate to the env var expected by code_coverage_checker.sh.
  if [[ -n "${coverage:-}" ]]; then
    export COVERAGE="$coverage"
  fi

  . "$(dirname "$BASH_SOURCE")/code_coverage_checker.sh"
}
