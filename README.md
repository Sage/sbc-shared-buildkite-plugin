# sbc-shared-buildkite-plugin
Collection of Sage specific functions used with Buildkite

## Coverage Gate Script

The `lib/code_coverage_checker.sh` script implements a coverage gate that validates PR coverage against a baseline branch.

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
| `BUILDKITE_PIPELINE_SLUG` | (from env) | Pipeline name; reads from `BUILDKITE_PIPELINE_SLUG` if set |
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

## Build and Push Strategy (Option C: Separate Image and Attestation Distribution)

### Build Phase (`buildx()`)
When building multi-platform images, the plugin creates separate tagged images for each architecture in BK_ECR:
- Accepts `--platforms linux/amd64,linux/arm64` parameter
- Builds each architecture separately with per-arch suffixes:
  - `BK_ECR:app-tag-build-123-amd64`
  - `BK_ECR:app-tag-build-123-arm64`
- Each build includes full attestations: `--provenance=mode=max --sbom=true`
- This avoids the manifest index intermediate artifact issue and ensures clean, tagged images

### Push Phase (`push_image()`)
The push flow distributes images and attestations in two coordinated steps:

1. **Copy per-arch images with referrers to target ECR** (via `oras cp -r`):
   - `BK_ECR:app-tag-build-123-amd64` → `TARGET_ECR:tag-x86_64` (with attestations)
   - `BK_ECR:app-tag-build-123-arm64` → `TARGET_ECR:tag-arm64` (with attestations)
   - ORAS copies image + all OCI referrers (signatures, SBOM, provenance, attestations)
   - Each per-arch image retains its own attestations

2. **Create OCI-compliant manifest index** (via `oras manifest index create`):
   - Composes final deployment manifest: `TARGET_ECR:tag` → points to arch-specific images
   - ORAS-based manifest creation preserves per-arch attestation metadata better than `docker buildx imagetools`

### Why This Approach Works
- **No untagged artifacts**: Per-arch images are explicitly tagged in BK_ECR → copied with tags → cleanup scripts won't remove them
- **Attestations preserved**: Each per-arch image carries its own build provenance, SBOM, and signatures through the copy
- **OCI-compliant**: Follows OCI Distribution Spec v1.1 for decoupled image and attestation distribution
- **ECR compatible**: Uses referrers API (`--from-distribution-spec v1.1-referrers-api`) for AWS ECR support

### Dependencies
- **Docker**: Required for buildx and containerized ORAS calls
- **ORAS v1.3.3**: Containerized as `ghcr.io/oras-project/oras:v1.3.3`
  - Replaces deprecated `cosign copy` command (deprecated Feb 2025, removed in Cosign v4)
  - Used for: per-arch image copying (`cp -r`) and manifest index creation (`manifest index create`)

### Credential Handling
- Mounts host Docker config directory (read-only) into ORAS containers
- Passes AWS credentials (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_SESSION_TOKEN, AWS_REGION, AWS_PROFILE) as environment variables
- Enables registry login reuse from earlier pipeline steps (ECR authentication, etc.)
