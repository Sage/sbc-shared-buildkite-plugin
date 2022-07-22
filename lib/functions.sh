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

  echo "Setting up variables for $1"

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
}

# convert --<switch> to a variable
switches() {
  echo "Processing switches"
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
  echo "Validating switches"

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
# tag => tag for the docker image
# file => source docker file to build from
# cache_id => cache identifier from where it was built from.  Typically GH branch name
buildx() {
  target=
  switches "$@"
  validate_switches tag file cache_id
  varx REPO

  echo "--- :building_construction: Build $tag"

  local OPTIONAL_TARGET=
  if [[ -n $target ]]; then
    OPTIONAL_TARGET="--target $target"
  fi

  docker buildx build \
    -f $file \
    --build-arg BUILDKIT_INLINE_CACHE=1 \
    --build-arg CI_BRANCH \
    --build-arg CI_STRING_TIME \
    --cache-from $BK_ECR:$APP-$tag-cache-$cache_id \
    --cache-from $BK_ECR:$APP-$tag-cache-master \
    --secret id=railslts,env=BUNDLE_GEMS__RAILSLTS__COM \
    --secret id=jfrog,env=BUNDLE_SAGEONEGEMS__JFROG__IO \
    --ssh default $OPTIONAL_TARGET \
    -t $REPO:$tag \
    .
}

# app => name of the application
# target => (Optional) set the target build stage to build
# tag => tag for the docker image
# file => source docker file to build from
# cache_id => cache identifier from where it was built from.  Typically GH branch name
buildx_and_cachex () {
  target=
  switches "$@"
  validate_switches app tag cache_id file
  varx REPO

  local OPTIONAL_TARGET=
  if [[ -n $target ]]; then
    OPTIONAL_TARGET="--target $target"
  fi

  buildx --app $app $OPTIONAL_TARGET --tag $tag --file $file --cache_id $cache_id
  
  cachex --app $app --tag $tag --cache_id $cache_id
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

# Push an image into the BK ECR for caching builds
cachex () {
  switches "$@"
  validate_switches app tag cache_id
  varx REPO

  echo "--- :s3: Cache $tag"
  local BUILD_IMAGE_NAME=$BK_ECR:$app-$tag-cache-$cache_id
  docker tag $REPO:$tag $BUILD_IMAGE_NAME
  docker push $BUILD_IMAGE_NAME
}

# Push an image into a target ECR for deployments
push_image () {
  switches "$@"
  validate_switches account_id app tag
  varx BUILDKITE_BUILD_NUMBER
  varx AWS_REGION
  varx BK_BRANCH  

  echo "Pushing image for $app"

  SOURCE_IMAGE=$BK_ECR:$app-$tag-build-$BUILDKITE_BUILD_NUMBER
  TARGET_IMAGE=$account_id.dkr.ecr.$AWS_REGION.amazonaws.com/$REPO:$BK_BRANCH
  docker pull $SOURCE_IMAGE
  docker tag $SOURCE_IMAGE $TARGET_IMAGE
  docker push $TARGET_IMAGE
}