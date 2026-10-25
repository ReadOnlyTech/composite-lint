#!/usr/bin/env bash
#
# Runs bin/lint.sh against the fixtures:
#   tests/pass/            everything is detected and lints clean
#   tests/fail/<lang>/<case>/  linting <lang> fails, with output matching the regex in <case>/expect
#
# Expects the tools to be installed already (bin/lint.sh install).

set -o pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2
lint=bin/lint.sh
readonly lint
failures=0

# plain output so expectations don't depend on CI annotation formats
unset GITHUB_ACTIONS

fail() {
  echo "FAIL: ${*}"
  failures=$((failures + 1))
}

expected='["actions","docker","go","pre-commit","python","shell","terraform","woke","yaml"]'
actual=$("${lint}" detect tests/pass)
readonly expected actual
if [[ ${actual} != "${expected}" ]]; then
  fail "detect tests/pass: expected ${expected}, got ${actual}"
else
  echo 'ok: detect tests/pass'
fi

if ! output=$("${lint}" tests/pass 2>&1); then
  echo "${output}"
  fail "tests/pass"
else
  echo 'ok: tests/pass'
fi

output=$(LINT_YAMLLINT_CONFIG=missing.yml "${lint}" --languages python,yaml tests/pass 2>&1)
status=${?}
if [[ ${status} -ne 2 || ${output} == *'== python =='* ]]; then
  echo "${output}"
  fail "invalid input: expected exit 2 before anything ran, got ${status}"
else
  echo 'ok: invalid input stops everything up front'
fi

# This golangci-lint version is never installed, and the system dirs won't have one to fall back on (unlike, e.g.,
# Homebrew's), so only the go checks should be skipped. Uses this Bash, since PATH no longer finds a modern one.
output=$(PATH=/usr/bin:/bin LINT_GOLANGCI_LINT_VERSION=0.0.1 "${BASH}" "${lint}" --languages go,python tests/pass 2>&1)
status=${?}
if [[ ${status} -ne 2 || ${output} != *'skipping go'* || ${output} != *'== python =='* ]]; then
  echo "${output}"
  fail "setup isolation: expected exit 2 with go skipped and python run, got ${status}"
else
  echo 'ok: a language that fails setup is skipped without stopping the others'
fi

# Without the guards, this config's hooks would run the linter again, which would run them again, and never finish
output=$(LINT_PRE_COMMIT_CONFIG=tests/pre-commit-nested.yaml "${lint}" --languages pre-commit tests/pass/pre-commit 2>&1)
status=${?}
if ((status)); then
  echo "${output}"
  fail "nested pre-commit: expected the hooks running composite-lint to be skipped, got ${status}"
else
  echo "ok: a pre-commit config that runs composite-lint doesn't recurse"
fi

for case in tests/fail/*/*/; do
  case=${case%/}
  lang=${case#tests/fail/}
  lang=${lang%%/*}
  expect=$(<"${case}/expect")

  if output=$("${lint}" --languages "${lang}" "${case}" 2>&1); then
    echo "${output}"
    fail "${case}: passed"
  # case dirs are often named after the rule, so don't let the paths in the output satisfy the expectation
  elif ! grep -Eq -- "${expect}" <<<"${output//"${case}"/}"; then
    echo "${output}"
    fail "${case}: output didn't match /${expect}/"
  else
    echo "ok: ${case}"
  fi
done
readonly failures

if ((failures)); then
  echo "${failures} failure(s)"
  exit 1
fi
echo 'All passed'
