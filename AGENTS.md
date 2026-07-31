This project is a plugin for the Buildkite continuous integration service. The plugin encapsulates business logic such as patterns for publishing Docker images and code for interacting with external services.

There is a test suite written with Bats. Most of the tests treat the plugin code as a black box and test its interfaces as executable code but some are more like unit tests of specific functions.

```
# Complete Bats suite
docker compose run --rm tests

# Focused test file with failure output
docker compose run --rm tests \
  bats --print-output-on-failure tests/post-command.bats

# Plugin schema and README lint
docker compose run --rm lint
```
