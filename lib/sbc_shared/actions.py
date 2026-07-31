from __future__ import annotations

import subprocess
from dataclasses import dataclass
from pathlib import Path
from typing import List, Mapping, Optional, Tuple


@dataclass(frozen=True)
class ImageConfig:
    account_id: str
    application: str
    variant: str
    multiarch: bool
    build_number: str
    region: str
    repository: str
    build_ecr: str
    target_tag: Optional[str] = None


@dataclass(frozen=True)
class ImagePush:
    target: str
    sources: Tuple[str, ...]

    @property
    def command(self) -> List[str]:
        return ["docker", "buildx", "imagetools", "create", "--tag", self.target] + list(
            self.sources
        )


def image_push(config: ImageConfig, branch: str) -> ImagePush:
    tag = config.target_tag or branch
    target = "{}.dkr.ecr.{}.amazonaws.com/{}:{}".format(
        config.account_id, config.region, config.repository, tag
    )
    image = "{}:{}-{}-build-{}".format(
        config.build_ecr, config.application, config.variant, config.build_number
    )
    sources = [image]
    if config.multiarch:
        sources.append(
            "{}:{}-{}-arm64-build-{}".format(
                config.build_ecr,
                config.application,
                config.variant,
                config.build_number,
            )
        )
    return ImagePush(target=target, sources=tuple(sources))


def require(environ: Mapping[str, str], *names: str) -> None:
    missing = [name for name in names if not environ.get(name)]
    if missing:
        raise ValueError("{} is not set.".format(missing[0]))


def config_for_variant(environ: Mapping[str, str], variant: str) -> ImageConfig:
    require(
        environ,
        "ACCOUNT_ID",
        "APP",
        "BUILDKITE_BUILD_NUMBER",
        "S1_REGION",
        "REPO",
        "BK_ECR",
    )
    return ImageConfig(
        account_id=environ["ACCOUNT_ID"],
        application=environ["APP"],
        variant=variant,
        multiarch=environ.get("MULTIARCH_IMAGE_PUSH", "false") == "true",
        build_number=environ["BUILDKITE_BUILD_NUMBER"],
        region=environ["S1_REGION"],
        repository=environ["REPO"],
        build_ecr=environ["BK_ECR"],
        target_tag=environ.get("TARGET_TAG") or None,
    )


def execute_image_push(config: ImageConfig, branch: str) -> int:
    push = image_push(config, branch)
    print(
        "Pushing image for {} using tag: {}".format(
            config.application, config.target_tag or branch
        )
    )
    if config.multiarch:
        print(
            "Creating multi-arch manifest: {} with {} and {}".format(
                push.target, push.sources[0], push.sources[1]
            )
        )
    else:
        print("Creating manifest: {} with {}".format(push.target, push.sources[0]))
    return subprocess.run(push.command, check=False).returncode


def push_images(environ: Mapping[str, str]) -> int:
    require(environ, "ENVIRONMENT", "APP", "DOCKER_TAG", "BK_BRANCH")
    initial_branch = environ["BK_BRANCH"]
    print(
        "--- :floppy_disk: Push {} image for {}".format(
            environ["ENVIRONMENT"], environ["APP"]
        )
    )

    result = execute_image_push(
        config_for_variant(environ, environ["DOCKER_TAG"]), initial_branch
    )
    if result:
        return result

    suffix = environ.get("BUILDKITE_PLUGIN_SBC_SHARED_EXTRA_SUFFIX")
    if suffix:
        suffix_config = config_for_variant(
            environ, "{}-{}".format(environ["DOCKER_TAG"], suffix)
        )
        result = execute_image_push(suffix_config, "{}-{}".format(initial_branch, suffix))
        if result:
            return result

    if environ["ENVIRONMENT"] != "qa" or environ.get("TARGET_TAG"):
        return 0

    if initial_branch == environ.get("BUILDKITE_PIPELINE_DEFAULT_BRANCH"):
        print("{} test image".format(environ["BUILDKITE_PIPELINE_DEFAULT_BRANCH"]))
        result = execute_image_push(
            config_for_variant(environ, "test"), "test-{}".format(initial_branch)
        )
        if result:
            return result

    if environ.get("HAS_DB_IMAGE") == "true":
        print("DB image")
        return execute_image_push(
            config_for_variant(environ, "database"), "database-{}".format(initial_branch)
        )
    return 0


def push_parameters(environ: Mapping[str, str], working_directory: Path) -> int:
    require(environ, "ENVIRONMENT", "LANDSCAPE", "S1_REGION")
    process_environment = dict(environ)
    process_environment["AWS_REGION"] = environ["S1_REGION"]
    return subprocess.run(
        ["./push.sh", "{}/{}".format(environ["ENVIRONMENT"], environ["LANDSCAPE"])],
        cwd=str(working_directory / "configuration"),
        env=process_environment,
        check=False,
    ).returncode


def run_build(environ: Mapping[str, str], working_directory: Path) -> int:
    script = """
if [[ -f .buildkite/custom_functions.sh ]]; then
  echo 'Loading custom file'
  source .buildkite/custom_functions.sh
fi
source .buildkite/build.sh
"""
    return subprocess.run(
        ["bash", "-euo", "pipefail", "-c", script],
        cwd=str(working_directory),
        env=dict(environ),
        check=False,
    ).returncode
