#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$($SCRIPT_DIR/build-app.sh)"
open "$APP_PATH"
