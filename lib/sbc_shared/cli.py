from __future__ import annotations

import os
import shutil
import subprocess
import sys
from datetime import datetime
from pathlib import Path
from typing import Sequence

from .actions import push_images, push_parameters, run_build
from .coverage import CoverageError, run_coverage_gate
from .environment import (
    PluginEnvironment,
    build_environment,
    ensure_buildx_builder,
    write_shell_environment,
)


def pre_command(arguments: Sequence[str]) -> int:
    if len(arguments) != 1:
        print("pre-command requires an environment output file", file=sys.stderr)
        return 2
    try:
        build = build_environment(os.environ, Path(".buildkite/.application"), datetime.now())
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1
    result = ensure_buildx_builder()
    if result:
        return result
    with Path(arguments[0]).open("w", encoding="utf-8") as output:
        write_shell_environment(output, build, PluginEnvironment.from_environ(os.environ))

    if os.environ.get("BUILDKITE_PLUGIN_SBC_SHARED_ACTION") == "publish_gem":
        destination = Path(".buildkite/release.sh")
        source = Path(__file__).resolve().parents[1] / "release_jfrog.sh"
        shutil.copyfile(str(source), str(destination))
        destination.chmod(0o755)
    return 0


def command() -> int:
    value = os.environ.get("BUILDKITE_COMMAND", "")
    if not value:
        return 0
    label = os.environ.get("BUILDKITE_LABEL")
    if label is None:
        print("BUILDKITE_LABEL is not set.", file=sys.stderr)
        return 1
    print("Step command detected for {}.  Executing command.".format(label))
    return subprocess.run(value, shell=True, executable="/bin/bash", check=False).returncode


def post_command() -> int:
    action = os.environ.get("BUILDKITE_PLUGIN_SBC_SHARED_ACTION", "")
    try:
        if action == "push_image":
            return push_images(os.environ)
        if action == "push_param":
            return push_parameters(os.environ, Path.cwd())
        if action == "publish_gem":
            print("")
            return 0
        if action == "build":
            return run_build(os.environ, Path.cwd())
        if action == "coverage_metrics":
            return run_coverage_gate(os.environ)
        print("Unsupported action name of {}".format(action))
        return 1
    except (ValueError, CoverageError) as error:
        print(error, file=sys.stderr)
        return 1


def main(arguments: Sequence[str]) -> int:
    if not arguments:
        print("Expected command, pre-command, post-command, or coverage", file=sys.stderr)
        return 2
    operation, rest = arguments[0], arguments[1:]
    if operation == "command":
        return command()
    if operation == "pre-command":
        return pre_command(rest)
    if operation == "post-command":
        return post_command()
    if operation == "coverage":
        try:
            return run_coverage_gate(os.environ)
        except CoverageError as error:
            print(error, file=sys.stderr)
            return 1
    print("Unknown operation: {}".format(operation), file=sys.stderr)
    return 2

