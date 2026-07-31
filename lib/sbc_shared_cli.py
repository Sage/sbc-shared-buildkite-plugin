#!/usr/bin/env python3
from __future__ import annotations

import sys

from sbc_shared.cli import main


if __name__ == "__main__":
    sys.stdout.reconfigure(line_buffering=True)
    sys.stderr.reconfigure(line_buffering=True)
    sys.exit(main(sys.argv[1:]))
