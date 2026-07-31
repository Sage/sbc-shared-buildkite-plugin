# sbc-shared-buildkite-plugin
Collection of Sage specific functions used with Buildkite

## Implementation

The Buildkite hook interfaces are kept in `hooks/`, while their self-contained
logic lives in the `lib/sbc_shared` Python package. `hooks/pre-command` remains
a small shell adapter because Buildkite needs its exports to affect the calling
shell. `lib/functions.sh` remains available as the public shell-function library
used by consuming repositories.

Python 3 is required on Buildkite agents. The Compose test service builds on the
standard plugin tester image and installs Python 3 for parity with those agents.

## Coverage Gate Script

The Python coverage implementation, also exposed through the compatible
`lib/code_coverage_checker.sh` entry point, validates PR coverage against a
baseline branch.

### What It Does

The coverage gate script performs the following steps:

1. **Resolves Baseline Build ID**
   - Queries the Buildkite API for the latest passed build on the configured baseline branch (`BASE_BRANCH`).

2. **Downloads Baseline Coverage Artifact**
   - Fetches coverage metrics from the baseline build using pagination.
   - Stores the artifact list in `base_artifacts.json`.
   - Downloads the baseline coverage file (default: `base-coverage-metrics.json`).
   - Extracts the line coverage percentage from the baseline.

3. **Downloads Current PR Coverage Artifact**
   - Fetches coverage metrics from the current build (PR/branch build).
   - Stores the artifact list in `patch_artifacts.json`.
   - Downloads the current coverage file (default: `current-coverage-metrics.json`).
   - Extracts the line coverage percentage from the PR.

4. **Compares Coverage Metrics**
   - Compares current PR coverage against a minimum allowed threshold.
   - Computes threshold as: `baseline coverage - COVERAGE_TOLERANCE` (floored at 0).
   - Fails (exit 1) if PR coverage is **below** the minimum allowed threshold.
   - Passes (exit 0) if PR coverage is **equal to or above** the minimum allowed threshold.
   - If `COVERAGE` is set, that value is used as baseline before tolerance is applied.

5. **Annotates Buildkite**
   - Posts a success annotation if coverage passes.
   - Posts an error annotation if coverage fails.

### Configuration

Environment variables to customize behavior:

| Variable | Default | Purpose |
|----------|---------|---------|
| `BUILDKITE_API_TOKEN` | (required) | Buildkite API token for authentication |
| `ORG` | `sage-group-plc` | Buildkite organization name |
| `BUILDKITE_PIPELINE_SLUG` | (from env) | Pipeline name; reads from `BUILDKITE_PIPELINE_SLUG` if set |
| `BASE_BRANCH` | `master` | Baseline branch for coverage comparison |
| `BUILDKITE_BUILD_NUMBER` | (from env) | Current build number (auto-set in CI) |
| `COVERAGE` | (unset) | Optional baseline override for coverage threshold |
| `COVERAGE_TOLERANCE` | `0.00` | Allowed reduction in coverage percentage points |
| `BASELINE_COVERAGE_ARTIFACT` | `coverage/.last_run.json` | Path to baseline coverage artifact in Buildkite |
| `CURRENT_COVERAGE_ARTIFACT` | `coverage/.last_run.json` | Path to current PR coverage artifact in Buildkite |
| `BASELINE_ARTIFACTS_JSON` | `base_artifacts.json` | Local filename for baseline artifact list |
| `CURRENT_ARTIFACTS_JSON` | `patch_artifacts.json` | Local filename for current artifact list |
| `BASELINE_COVERAGE_FILE` | `base-coverage-metrics.json` | Local filename for baseline coverage data |
| `CURRENT_COVERAGE_FILE` | `current-coverage-metrics.json` | Local filename for current coverage data |

### Usage in Buildkite Pipeline

```yaml
- label: ':bar_chart: Code coverage regression'
  retry:
    automatic:
      signal_reason: agent_stop
  plugins:
    - ecr#v2.9.0:
        login: true
        account-ids: '522104923602'
        region: 'eu-west-1'
        assume_role:
        role_arn: 'arn:aws:iam::522104923602:role/CI.Integration'
    - ssh://git@github.com/Sage/sbc-shared-buildkite-plugin.git#2.9.0:
        action: coverage_metrics
```
## Testing

To run the test suite:

```
docker compose run --rm tests
```

Or to do it with debugging enabled, use:
```
docker compose run --rm tests bats --print-output-on-failure tests
```
