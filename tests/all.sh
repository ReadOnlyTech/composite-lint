#!/usr/bin/env bash
#
# Installs every language's linters, then runs each test suite, carrying on past failures. Exits 1
# if any suite failed. CI and the repo's pre-commit config both run this.

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

failed=()

suite() {
  local -r command=("${@}")
  echo "== ${command[*]}"
  "${command[@]}" || failed+=("${command[*]}")
}

# the fixtures need every language's tools, so it installs for the whole repo
suite bin/lint.sh install
suite tests/run.sh
suite tests/tag_release.sh
suite tests/bump_tool_versions.py

if ((${#failed[@]})); then
  printf 'FAILED: %s\n' "${failed[@]}"
  exit 1
fi
