#!/usr/bin/env python3
from __future__ import annotations

import glob
import os
import subprocess
import sys
from pathlib import Path


def require(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise ValueError("{} is not set.".format(name))
    return value


def main() -> int:
    try:
        application = require("APP")
        user = require("ART_USER")
        password = require("ART_PASS")
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1

    result = subprocess.run(
        ["bundle", "exec", "rake", "build", "{}.gemspec".format(application)], check=False
    )
    if result.returncode:
        return result.returncode

    host = os.environ.get("GEM_HOST") or (
        "https://sageonegems.jfrog.io/sageonegems/api/gems/gems-local"
    )
    print("Gems Host: {}".format(host))
    credentials = Path.home() / ".gem" / "credentials"
    credentials.parent.mkdir(parents=True, exist_ok=True)
    with credentials.open("wb") as output:
        result = subprocess.run(
            ["curl", "-u", "{}:{}".format(user, password), host + "/api/v1/api_key.yaml"],
            stdout=output,
            check=False,
        )
    if result.returncode:
        return result.returncode
    credentials.chmod(0o600)

    pattern = os.environ.get("GEM_PATH") or "pkg/*.gem"
    print("Gem Path: {}".format(pattern))
    gems = glob.glob("/usr/src/app/" + pattern)
    if not gems:
        print("No gems matched /usr/src/app/{}".format(pattern), file=sys.stderr)
        return 1
    for gem in gems:
        result = subprocess.run(
            ["gem", "push", gem],
            env=dict(os.environ, RUBYGEMS_HOST=host),
            check=False,
        )
        if result.returncode:
            return result.returncode
    print("Push Complete")
    return 0


if __name__ == "__main__":
    sys.exit(main())
