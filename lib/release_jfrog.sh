#!/usr/bin/env bash

set -e

bundle exec rake build $APP.gemspec

local RUBYGEMS_HOST=${GEM_HOST:-"https://sageonegems.jfrog.io/sageonegems/api/gems/gems-local"}

echo "Gems Host: $RUBYGEMS_HOST"

mkdir -p ~/.gem
curl -u $ART_USER:$ART_PASS $RUBYGEMS_HOST/api/v1/api_key.yaml > ~/.gem/credentials
chmod 600 ~/.gem/credentials

local GEMS_PATH=${GEM_PATH:-"pkg/*.gem"}

echo "Gem Path: $GEMS_PATH"

gem push /usr/src/app/$GEMS_PATH

echo "Push Complete"