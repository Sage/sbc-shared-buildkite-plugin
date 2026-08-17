#!/usr/bin/env bash
set -euo pipefail

: "${VEX_OUTPUT_FILE:?VEX_OUTPUT_FILE is required}"

printf '%s\n' "$VEX_OUTPUT_FILE"
