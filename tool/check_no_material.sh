#!/usr/bin/env bash
# Fails if any Dart file imports Material. Run in CI next to `flutter analyze`.
set -euo pipefail
cd "$(dirname "$0")/.."
if grep -rnE "package:flutter/material\.dart|(^|[^A-Za-z_])Icons\." lib test; then
  echo "Material import/usage found — this app is Cupertino-only." >&2
  exit 1
fi
echo "OK: no Material usage."
