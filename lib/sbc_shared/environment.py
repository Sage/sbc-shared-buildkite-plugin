from __future__ import annotations

import os
import shlex
import subprocess
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Dict, Mapping, Optional, TextIO


@dataclass(frozen=True)
class BuildEnvironment:
    application: str
    repository: str
    branch: str
    commit: str
    timestamp: str
    build_ecr: str
    build_cache: str
    buildkit_progress: Optional[str]

    def exports(self) -> Dict[str, str]:
        values = {
            "APP": self.application,
            "REPO": self.repository,
            "BK_BRANCH": self.branch,
            "CI_BRANCH": self.branch,
            "CI_COMMIT": self.commit,
            "CI_STRING_TIME": self.timestamp,
            "BK_ECR": self.build_ecr,
            "BK_CACHE": self.build_cache,
        }
        if self.buildkit_progress is not None:
            values["BUILDKIT_PROGRESS"] = self.buildkit_progress
        return values


@dataclass(frozen=True)
class PluginEnvironment:
    values: Mapping[str, Optional[str]]

    @classmethod
    def from_environ(cls, environ: Mapping[str, str]) -> "PluginEnvironment":
        def configured(name: str, fallback: Optional[str] = None) -> Optional[str]:
            value = environ.get("BUILDKITE_PLUGIN_SBC_SHARED_" + name)
            if not value:
                value = fallback
            return value or None

        values: Dict[str, Optional[str]] = {
            "ENVIRONMENT": configured("ENVIRONMENT"),
            "LANDSCAPE": configured("LANDSCAPE"),
            "ACCOUNT_ID": configured("ACCOUNT_ID"),
            "GEM_HOST": configured("GEM_HOST"),
            "COVERAGE": configured("COVERAGE", environ.get("COVERAGE")),
            "COVERAGE_TOLERANCE": configured(
                "COVERAGE_TOLERANCE", environ.get("COVERAGE_TOLERANCE")
            ),
            "TARGET_TAG": environ.get("BUILDKITE_PLUGIN_SBC_SHARED_TARGET_TAG", ""),
            "DOCKER_TAG": environ.get("BUILDKITE_PLUGIN_SBC_SHARED_TAG")
            or "application",
            "HAS_DB_IMAGE": environ.get("BUILDKITE_PLUGIN_SBC_SHARED_DB_IMAGE")
            or "false",
            "MULTIARCH_IMAGE_PUSH": environ.get(
                "BUILDKITE_PLUGIN_SBC_SHARED_MULTIARCH_IMAGE_PUSH"
            )
            or "false",
        }
        region = configured("REGION")
        if region is not None:
            values["S1_REGION"] = region
        return cls(values)


def build_environment(
    environ: Mapping[str, str], application_file: Path, now: datetime
) -> BuildEnvironment:
    prefix = environ.get("BUILDKITE_PLUGIN_SBC_SHARED_REPO_PREFIX") or "sageone"

    try:
        application = application_file.read_text(encoding="utf-8").strip()
    except OSError as error:
        raise ValueError("Unable to read {}: {}".format(application_file, error))
    if not application:
        raise ValueError("{} is empty".format(application_file))

    branch = os.path.basename(environ.get("BUILDKITE_BRANCH", ""))
    branch = branch or environ.get("BUILDKITE_TAG", "")
    region = environ.get("AWS_REGION")
    if not region:
        raise ValueError("AWS_REGION is not set.")

    ecr = "268539851198.dkr.ecr.{}.amazonaws.com/sageone".format(region)
    return BuildEnvironment(
        application=application,
        repository="{}/{}".format(prefix, application),
        branch=branch,
        commit=environ.get("BUILDKITE_COMMIT", ""),
        timestamp=now.strftime("%Y-%m-%d %H:%M:%S"),
        build_ecr=ecr + "/buildkite",
        build_cache=ecr + "/cache",
        buildkit_progress="plain" if environ.get("BUILDKITE") == "true" else None,
    )


def ensure_buildx_builder() -> int:
    inspected = subprocess.run(
        ["docker", "buildx", "inspect", "buildx-builder"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if inspected.returncode == 0:
        return 0
    return subprocess.run(
        [
            "docker",
            "buildx",
            "create",
            "--driver",
            "docker-container",
            "--name",
            "buildx-builder",
            "--use",
            "--bootstrap",
        ],
        check=False,
    ).returncode


def write_shell_environment(
    output: TextIO,
    build: BuildEnvironment,
    plugin: PluginEnvironment,
) -> None:
    values: Dict[str, Optional[str]] = dict(build.exports())
    values.update(plugin.values)
    for name, value in values.items():
        if value is None:
            output.write("unset {}\n".format(name))
        else:
            output.write("export {}={}\n".format(name, shlex.quote(value)))
