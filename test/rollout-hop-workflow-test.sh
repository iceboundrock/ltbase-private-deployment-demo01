#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKFLOW_PATH="${ROOT_DIR}/.github/workflows/rollout-hop.yml"

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_contains() {
  local path="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$path"; then
    fail "expected ${path} to contain: ${needle}"
  fi
}

assert_file_missing() {
  local path="$1"
  local needle="$2"
  if grep -Fq "$needle" "$path"; then
    fail "expected ${path} to not contain: ${needle}"
  fi
}

if [[ ! -f "${WORKFLOW_PATH}" ]]; then
  fail "missing workflow: ${WORKFLOW_PATH}"
fi

assert_file_contains "${WORKFLOW_PATH}" 'publish_schemas:'
assert_file_contains "${WORKFLOW_PATH}" 'ensure_project:'
assert_file_missing "${WORKFLOW_PATH}" "needs.rollout.result == 'success'"
assert_file_missing "${WORKFLOW_PATH}" "needs.publish_schemas.result == 'success'"

printf 'PASS: rollout hop workflow tests\n'
