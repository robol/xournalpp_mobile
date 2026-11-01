#!/usr/bin/env bash
set -euo pipefail
repo_root=$(cd "$(dirname "$0")/.." && pwd)
test_output=$(mktemp -d)
trap 'rm -rf "$test_output"' EXIT
javac -d "$test_output" \
  "$repo_root/android/app/src/main/kotlin/it/robol/xournal/mobile/SafOverwrite.java" \
  "$repo_root/android/app/src/test/java/it/robol/xournal/mobile/SafOverwriteFaultTest.java"
java -cp "$test_output" it.robol.xournal.mobile.SafOverwriteFaultTest
