varx () {
  if [[ -z "${!1}" ]]; then
    echo "$1 is not set."
    exit 1
  fi
}

setup() {
  if [ -z $1 ]; then
    echo "Please define a repo prefix name (e.g. setup sageone)"
    exit 1
  fi

  # Setup the env that contains the application name and repo name
  export APP=$(cat .buildkite/.application)
  export REPO=$1/$APP

  # Setup the proper docker tag to be used depending on GH tag and/or branch
  export BK_BRANCH="${BUILDKITE_BRANCH:-$BUILDKITE_TAG}"

  # Setup CI branch and time used by various other tools. E.g. ssm pusher
  export CI_STRING_TIME=$(date '+%Y-%m-%d %H:%M:%S')
  export CI_BRANCH=$BK_BRANCH

  # Change the output of the docker build process to not be truncated in BK
  if [[ "$BUILDKITE" == "true" ]]; then
    export BUILDKIT_PROGRESS=plain
  fi

  export BK_ECR=268539851198.dkr.ecr.eu-west-1.amazonaws.com/sageone/buildkite
  export BK_CACHE=268539851198.dkr.ecr.eu-west-1.amazonaws.com/sageone/cache

  # Needed for --cache-from and --cache-to
  docker buildx create --use --bootstrap
}

# convert --<switch> to a variable
switches() {
  while [ $# -gt 0 ]; do
   if [[ $1 == *"--"* ]]; then
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

# target => (Optional) set the target build stage to build
# tag => variant of the docker image e.g. app or database
# file => source Dockerfile
# cache_id => typically the git branch name
buildx() {
  target=
  switches "$@"
  validate_switches tag file cache_id
  varx REPO
  varx BUILDKITE_PIPELINE_DEFAULT_BRANCH

  echo "+++ :building_construction: Build $tag"

  local OPTIONAL_TARGET=
  if [[ -n $target ]]; then
    OPTIONAL_TARGET="--target $target"
  fi

  docker buildx build \
    -f $file \
    --build-arg CI_BRANCH \
    --build-arg CI_STRING_TIME \
    --cache-to mode=max,image-manifest=true,oci-mediatypes=true,type=registry,ref=$BK_CACHE:$APP-$tag-$cache_id \
    --cache-from $BK_CACHE:$APP-$tag-$cache_id \
    --cache-from $BK_CACHE:$APP-$tag-$BUILDKITE_PIPELINE_DEFAULT_BRANCH \
    --secret id=railslts,env=BUNDLE_GEMS__RAILSLTS__COM \
    --secret id=jfrog,env=BUNDLE_SAGEONEGEMS__JFROG__IO \
    --secret id=jfrog_npm,env=SAGEONEGEMS_JFROG_NPM_TOKEN \
    --ssh default \
    $OPTIONAL_TARGET \
    --load \
    -t $REPO:$tag \
    .
}


# Push an image into the BK ECR
pushx () {
  switches "$@"
  validate_switches app tag
  varx REPO
  varx BUILDKITE_BUILD_NUMBER

  echo "--- :floppy_disk: Push $tag"
  local BUILD_IMAGE_NAME=$BK_ECR:$app-$tag-build-$BUILDKITE_BUILD_NUMBER
  docker tag  $REPO:$tag $BUILD_IMAGE_NAME
  docker push $BUILD_IMAGE_NAME
}

# Push an image into a target ECR for deployments
push_image () {
  switches "$@"
  validate_switches account_id app tag multiarch
  varx BUILDKITE_BUILD_NUMBER
  varx AWS_REGION
  varx BK_BRANCH

  # If the override ENV option was specified in the pipeline, use that tag value.
  # This supports custom tags like `last-successful-build` that don't match the GH tag/branch that triggered the commit
  local target_tag=${TARGET_TAG:-$BK_BRANCH}

  echo "Pushing image for $app using tag: $target_tag"

  local X86_64_TAG_SUFFIX=""

  if [[ "$multiarch" == "true" ]]; then
    X86_64_TAG_SUFFIX=-x86_64
  fi

  TARGET_ECR=$account_id.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO:$target_tag

  SOURCE_IMAGE_X86_64=$BK_ECR:$app-$tag-build-$BUILDKITE_BUILD_NUMBER
  TARGET_IMAGE_X86_64=$TARGET_ECR$X86_64_TAG_SUFFIX
  docker pull $SOURCE_IMAGE_X86_64
  docker tag $SOURCE_IMAGE_X86_64 $TARGET_IMAGE_X86_64
  docker push $TARGET_IMAGE_X86_64

  if [[ "$multiarch" == "true" ]]; then
    SOURCE_IMAGE_ARM64=$BK_ECR:$app-$tag-arm64-build-$BUILDKITE_BUILD_NUMBER
    TARGET_IMAGE_ARM64=$TARGET_ECR-arm64
    docker pull $SOURCE_IMAGE_ARM64
    docker tag $SOURCE_IMAGE_ARM64 $TARGET_IMAGE_ARM64
    docker push $TARGET_IMAGE_ARM64

    # Create & push manifest file for multiarch image
    docker manifest create $TARGET_ECR $TARGET_IMAGE_X86_64 $TARGET_IMAGE_ARM64
    docker manifest push $TARGET_ECR
  fi
}
