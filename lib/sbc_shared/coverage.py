from __future__ import annotations

import json
import shutil
import subprocess
import sys
from dataclasses import dataclass
from decimal import Decimal, InvalidOperation
from pathlib import Path
from typing import Any, Mapping, Optional
from urllib.parse import quote


class CoverageError(Exception):
    pass


class ArtifactMissing(Exception):
    pass


def percentage(value: str, name: str) -> Decimal:
    try:
        parsed = Decimal(value)
    except (InvalidOperation, TypeError, ValueError):
        raise CoverageError(
            "{} must be a non-negative numeric value (e.g. 0, 0.25, 1.5).".format(name)
        )
    if not parsed.is_finite() or parsed < 0:
        raise CoverageError(
            "{} must be a non-negative numeric value (e.g. 0, 0.25, 1.5).".format(name)
        )
    return parsed


@dataclass(frozen=True)
class CoverageConfig:
    api_token: str
    organization: str
    pipeline: str
    base_branch: str
    build_number: str
    baseline_artifact: str
    current_artifact: str
    tolerance: Decimal
    baseline_artifacts_file: Path
    baseline_coverage_file: Path
    current_artifacts_file: Path
    current_coverage_file: Path
    coverage_override: Optional[Decimal]
    base_build_id: Optional[str]

    @classmethod
    def from_environ(cls, environ: Mapping[str, str]) -> "CoverageConfig":
        def configured(name: str, default: str) -> str:
            return environ.get(name) or default

        token = environ.get("BUILDKITE_API_TOKEN", "")
        pipeline = environ.get("BUILDKITE_PIPELINE_SLUG", "")
        build_number = environ.get("BUILDKITE_BUILD_NUMBER", "")
        if not token:
            raise CoverageError("BUILDKITE_API_TOKEN is not set in this step environment.")
        if not pipeline:
            raise CoverageError(
                "BUILDKITE_PIPELINE_SLUG must be set to resolve Buildkite artifacts."
            )
        if not build_number:
            raise CoverageError(
                "BUILDKITE_BUILD_NUMBER must be set to resolve current build artifacts."
            )
        tolerance = percentage(
            configured("COVERAGE_TOLERANCE", "0.00"), "COVERAGE_TOLERANCE"
        )
        override_value = environ.get("COVERAGE") or None
        override = percentage(override_value, "COVERAGE") if override_value else None
        return cls(
            api_token=token,
            organization=configured("ORG", "sage-group-plc"),
            pipeline=pipeline,
            base_branch=environ.get("BASE_BRANCH")
            or environ.get("BUILDKITE_PIPELINE_DEFAULT_BRANCH")
            or "master",
            build_number=build_number,
            baseline_artifact=configured(
                "BASELINE_COVERAGE_ARTIFACT", "coverage/.last_run.json"
            ),
            current_artifact=configured(
                "CURRENT_COVERAGE_ARTIFACT", "coverage/.last_run.json"
            ),
            tolerance=tolerance,
            baseline_artifacts_file=Path(
                configured("BASELINE_ARTIFACTS_JSON", "base_artifacts.json")
            ),
            baseline_coverage_file=Path(
                configured("BASELINE_COVERAGE_FILE", "base-coverage-metrics.json")
            ),
            current_artifacts_file=Path(
                configured("CURRENT_ARTIFACTS_JSON", "patch_artifacts.json")
            ),
            current_coverage_file=Path(
                configured("CURRENT_COVERAGE_FILE", "current-coverage-metrics.json")
            ),
            coverage_override=override,
            base_build_id=environ.get("BASE_BUILD_ID") or None,
        )


class BuildkiteClient:
    def __init__(self, config: CoverageConfig):
        self.config = config
        self.base_url = "https://api.buildkite.com/v2/organizations/{}/pipelines/{}".format(
            config.organization, config.pipeline
        )

    def _curl(self, url: str, output: Optional[Path] = None) -> str:
        command = ["curl", "-sS"]
        if output is not None:
            command.append("-L")
        command.extend(
            ["-H", "Authorization: Bearer {}".format(self.config.api_token), url]
        )
        if output is not None:
            command.extend(["-o", str(output)])
        completed = subprocess.run(
            command,
            stdout=subprocess.PIPE if output is None else None,
            text=True,
            check=False,
        )
        if completed.returncode:
            raise CoverageError("Buildkite API request failed for {}".format(url))
        return completed.stdout if output is None else ""

    def api_get(self, path: str) -> str:
        return self._curl("{}/{}".format(self.base_url, path))

    def latest_passed_build_id(self) -> str:
        response = self.api_get(
            "builds?branch={}&state=passed&page=1&per_page=100".format(
                quote(self.config.base_branch, safe="")
            )
        )
        if not response:
            raise CoverageError(
                "API returned empty response for branch: {}".format(self.config.base_branch)
            )
        try:
            builds = json.loads(response)
            return str(builds[0]["number"])
        except (ValueError, IndexError, KeyError, TypeError):
            raise CoverageError(
                "No passed builds found for branch: {}\nAPI response: {}".format(
                    self.config.base_branch, response
                )
            )

    def find_artifact_url(self, build_id: str, artifact_path: str, output: Path) -> str:
        page = 1
        while True:
            response = self.api_get(
                "builds/{}/artifacts?page={}&per_page=100".format(build_id, page)
            )
            output.write_text(response, encoding="utf-8")
            try:
                artifacts = json.loads(response)
            except ValueError:
                raise CoverageError("Invalid artifact response for build {}".format(build_id))
            if not artifacts:
                raise ArtifactMissing()
            for artifact in artifacts:
                if artifact.get("path") == artifact_path and artifact.get("download_url"):
                    return str(artifact["download_url"])
            page += 1

    def download(self, url: str, output: Path) -> None:
        self._curl(url, output)


def find_line_coverage(value: Any) -> Decimal:
    if isinstance(value, dict):
        if "line" in value:
            return percentage(str(value["line"]), "line coverage")
        for child in value.values():
            try:
                return find_line_coverage(child)
            except CoverageError:
                pass
    elif isinstance(value, list):
        for child in value:
            try:
                return find_line_coverage(child)
            except CoverageError:
                pass
    raise CoverageError("Unable to parse coverage values from baseline/current JSON files.")


def read_coverage(path: Path) -> Decimal:
    try:
        return find_line_coverage(json.loads(path.read_text(encoding="utf-8")))
    except (OSError, ValueError):
        raise CoverageError("Unable to parse coverage values from baseline/current JSON files.")


def display(value: Decimal) -> str:
    return str(value)


def annotate(style: str, message: str) -> None:
    if shutil.which("buildkite-agent"):
        subprocess.run(
            [
                "buildkite-agent",
                "annotate",
                "--style",
                style,
                "--context",
                "coverage-gate",
                message,
            ],
            check=False,
        )


def download_metrics(
    client: BuildkiteClient,
    build_id: str,
    artifact_path: str,
    artifacts_file: Path,
    coverage_file: Path,
    label: str,
) -> bool:
    try:
        url = client.find_artifact_url(build_id, artifact_path, artifacts_file)
    except ArtifactMissing:
        url = ""
    print("{} download URL: {}".format(label, url))
    if not url:
        message = (
            "Coverage gate skipped: {} artifact '{}' is not available for build {}. "
            "Coverage comparison was not performed."
        ).format(label, artifact_path, build_id)
        print(
            "Artifact path '{}' was not found for build {}.".format(artifact_path, build_id),
            file=sys.stderr,
        )
        annotate("warning", message)
        return False
    client.download(url, coverage_file)
    return True


def run_coverage_gate(environ: Mapping[str, str]) -> int:
    config = CoverageConfig.from_environ(environ)
    client = BuildkiteClient(config)
    base_build_id = config.base_build_id or client.latest_passed_build_id()
    print("Resolved BASE_BUILD_ID: {}".format(base_build_id))

    if not download_metrics(
        client,
        base_build_id,
        config.baseline_artifact,
        config.baseline_artifacts_file,
        config.baseline_coverage_file,
        "Baseline",
    ):
        return 0
    if not download_metrics(
        client,
        config.build_number,
        config.current_artifact,
        config.current_artifacts_file,
        config.current_coverage_file,
        "Current",
    ):
        return 0

    baseline = read_coverage(config.baseline_coverage_file)
    current = read_coverage(config.current_coverage_file)
    print("Downloaded baseline coverage: {}%".format(display(baseline)))
    print("Current coverage: {}%".format(display(current)))

    baseline_label = "{} baseline".format(config.base_branch)
    if config.coverage_override is not None:
        baseline = config.coverage_override
        baseline_label = "configured COVERAGE threshold"
        print("Using COVERAGE threshold: {}%".format(display(baseline)))

    minimum = max(Decimal("0"), baseline - config.tolerance)
    minimum_text = "{:.2f}".format(minimum)
    print("Active baseline: {}% ({})".format(display(baseline), baseline_label))
    print("Coverage tolerance: {}%".format(display(config.tolerance)))
    print("Minimum allowed coverage: {}%".format(minimum_text))

    details = "PR={}% baseline={}% tolerance={}% minimum={}% source={}.".format(
        display(current),
        display(baseline),
        display(config.tolerance),
        minimum_text,
        baseline_label,
    )
    if current < minimum:
        print(
            "FAIL: PR coverage ({}%) is below the minimum allowed coverage ({}%).".format(
                display(current), minimum_text
            )
        )
        annotate("error", "Coverage regression failed: " + details)
        return 1
    print(
        "OK: PR coverage ({}%) is within tolerance of the {} ({}%).".format(
            display(current), baseline_label, display(baseline)
        )
    )
    annotate("success", "Coverage regression passed: " + details)
    return 0
