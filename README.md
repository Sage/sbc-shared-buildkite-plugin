# sbc-shared-buildkite-plugin
Collection of Sage specific functions used with Buildkite

## Coverage Gate Script

The `lib/code_coverage_checker.sh` script implements a coverage gate that validates PR coverage against a baseline branch.

### What It Does

The coverage gate script performs the following steps:

1. **Resolves Baseline Build ID**
   - Queries the Buildkite API for the latest passed build on the baseline branch.
   - Falls back to alternative branches (`master`).
   - Ensures you always compare against a valid baseline.

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
   - Compares current PR coverage against baseline coverage.
   - Fails (exit 1) if PR coverage is **below** baseline
   - Passes (exit 0) if PR coverage is **equal to or above** baseline.

5. **Annotates Buildkite**
   - Posts a success annotation if coverage passes.
   - Posts an error annotation if coverage fails.

### Configuration

Environment variables to customize behavior:

| Variable | Default | Purpose |
|----------|---------|---------|
| `BUILDKITE_API_TOKEN` | (required) | Buildkite API token for authentication |
| `ORG` | `sage-group-plc` | Buildkite organization name |
| `BUILDKITE_PIPELINE_NAME` | (from env) | Pipeline name; reads from `BUILDKITE_PIPELINE_SLUG` if set |
| `BASE_BRANCH` | `master` | Baseline branch for coverage comparison |
| `BUILDKITE_BUILD_NUMBER` | (from env) | Current build number (auto-set in CI) |
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
    agents:
      queue: bk-apse2-x86
```
