#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
TEST_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_DIR"' EXIT

swiftc \
  -framework AppKit \
  "$ROOT_DIR/Sources/CodexExecutableLocator.swift" \
  "$ROOT_DIR/Tests/CodexExecutableLocatorTests.swift" \
  -o "$TEST_DIR/CodexExecutableLocatorTests"

"$TEST_DIR/CodexExecutableLocatorTests"
