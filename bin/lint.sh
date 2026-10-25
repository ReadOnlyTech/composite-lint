#!/usr/bin/env bash
#
# Detects which languages are present, installs pinned linters for them, and runs them.
#
# Usage:
#   lint [run]   [--languages a,b] [--exclude pathspec]... [path...]
#   lint detect  [--languages a,b] [--exclude pathspec]... [path...]
#   lint install [--languages a,b] [--exclude pathspec]... [path...]
#   lint versions [--languages a,b] [--exclude pathspec]... [path...]   # each needed tool and its version
#   lint version <tool>
#
# Options can also come from LINT_LANGUAGES, LINT_EXCLUDE and LINT_PATHS (whitespace-separated).
# Per-tool settings come from the environment, e.g. for golangci-lint:
#   LINT_GOLANGCI_LINT_VERSION       raw version, e.g. v2.14.0 (the `v` is optional)
#   LINT_GOLANGCI_LINT_VERSION_FILE  path to a file containing the version
#   LINT_GOLANGCI_LINT_CONFIG        path to a config file
# Anything not set falls back to what's bundled in versions/ and configs/.
#
# All inputs are validated before anything is installed or run. After that, a language whose tools
# can't be installed or found fails on its own and the other languages still run.
#
# Exit codes: 0 clean, 1 lint failures, 2 invalid usage/inputs or a language couldn't be set up.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LANGUAGES='actions docker go python shell terraform woke yaml'
PIP_TOOLS=' flake8 yamllint zizmor '
CACHE=${LINT_CACHE:-${RUNNER_TOOL_CACHE:-${XDG_CACHE_HOME:-${HOME}/.cache}}/composite-lint}
readonly ROOT LANGUAGES PIP_TOOLS CACHE

die() {
  echo "lint: ${*}" >&2
  exit 2
}

warn() {
  if [[ -n ${GITHUB_ACTIONS:-} ]]; then
    echo "::warning::${*}"
  else
    echo "lint: warning: ${*}" >&2
  fi
}

# Like die, but leaves it to the caller to carry on
error() {
  if [[ -n ${GITHUB_ACTIONS:-} ]]; then
    echo "::error::${*}"
  else
    echo "lint: error: ${*}" >&2
  fi
}

group() {
  if [[ -n ${GITHUB_ACTIONS:-} ]]; then
    echo "::group::${*}"
  else
    echo "== ${*} =="
  fi
}

endgroup() {
  if [[ -n ${GITHUB_ACTIONS:-} ]]; then
    echo '::endgroup::'
  fi
}

# Splits on whitespace and commas without globbing, e.g. `split ARR "${value}"`
split() {
  IFS=$' \t\n,' read -r -d '' -a "${1}" <<<"${2}" || true
}

trim() {
  local s=${1}
  s=${s#"${s%%[![:space:]]*}"}
  echo "${s%"${s##*[![:space:]]}"}"
}

abspath() {
  echo "$(cd "$(dirname "${1}")" && pwd)/$(basename "${1}")"
}

# --- versions and configs ---

env_key() {
  echo "LINT_$(echo "${1}" | tr '[:lower:]-' '[:upper:]_')"
}

# First non-blank, non-comment line
read_version_file() {
  local line
  while IFS= read -r line || [[ -n ${line} ]]; do
    line=$(trim "${line%%#*}")
    if [[ -n ${line} ]]; then
      echo "${line}"
      return
    fi
  done <"${1}"
}

version() {
  local key raw file v
  key=$(env_key "${1}")
  raw=${key}_VERSION
  raw=${!raw:-}
  file=${key}_VERSION_FILE
  file=${!file:-}
  readonly key raw file

  if [[ -n ${raw} && -n ${file} ]]; then
    die "set only one of ${key}_VERSION and ${key}_VERSION_FILE"
  elif [[ -n ${raw} ]]; then
    v=${raw}
  elif [[ -n ${file} ]]; then
    [[ -f ${file} ]] || die "${key}_VERSION_FILE: ${file} not found"
    v=$(read_version_file "${file}")
  elif [[ -f ${ROOT}/versions/.${1}-version ]]; then
    v=$(read_version_file "${ROOT}/versions/.${1}-version")
  else
    v=$(sed -n "s/^${1}==//p" "${ROOT}/versions/pip/requirements.txt")
  fi
  readonly v

  [[ -n ${v} ]] || die "no version found for ${1}"

  # Inputs may come with or without a `v`. Release downloads are tagged with one; pip and Terraform aren't.
  if is_pip "${1}" || [[ ${1} == terraform ]]; then
    echo "${v#v}"
  else
    echo "v${v#v}"
  fi
}

bundled_config() {
  case ${1} in
    actionlint) echo actionlint.yml ;;
    flake8) echo flake8.ini ;;
    hadolint) echo hadolint.yml ;;
    shellcheck) echo shellcheckrc ;;
    tflint) echo tflint.hcl ;;
    yamllint) echo yamllint.yml ;;
    zizmor) echo zizmor.yml ;;
  esac
}

# Absolute path to the config to use, or nothing if there's neither an input nor a bundled one
config() {
  local var path bundled
  var=$(env_key "${1}")_CONFIG
  path=${!var:-}
  bundled=$(bundled_config "${1}")
  readonly var path bundled

  if [[ -n ${path} ]]; then
    [[ -f ${path} ]] || die "${var}: ${path} not found"
    abspath "${path}"
  elif [[ -n ${bundled} ]]; then
    echo "${ROOT}/configs/${bundled}"
  fi
}

# --- tool installation ---

tools_for() {
  case ${1} in
    actions) echo actionlint shellcheck zizmor ;;
    docker) echo hadolint ;;
    go) echo golangci-lint ;;
    python) echo flake8 ;;
    shell) echo shellcheck ;;
    terraform) echo tflint ;;
    woke) echo woke ;;
    yaml) echo yamllint ;;
  esac
}

is_pip() {
  [[ ${PIP_TOOLS} == *" ${1} "* ]]
}

tool_dir() {
  local v
  v=$(version "${1}")
  readonly v
  if is_pip "${1}"; then
    echo "${CACHE}/venv/${1}-${v}/bin"
  else
    echo "${CACHE}/tools/${1}/${v}"
  fi
}

platform() {
  OS=$(uname -s | tr '[:upper:]' '[:lower:]')
  case $(uname -m) in
    x86_64 | amd64) ARCH=amd64 ;;
    aarch64 | arm64) ARCH=arm64 ;;
    *) die "unsupported architecture: $(uname -m)" ;;
  esac
  readonly OS ARCH
}

# Takes the release tag; some asset names use the version without its `v`
binary_url() {
  local tag=${2} v=${2#v} gh=https://github.com
  readonly tag v gh
  case ${1} in
    actionlint)
      echo "${gh}/rhysd/actionlint/releases/download/${tag}/actionlint_${v}_${OS}_${ARCH}.tar.gz" ;;
    golangci-lint)
      echo "${gh}/golangci/golangci-lint/releases/download/${tag}/golangci-lint-${v}-${OS}-${ARCH}.tar.gz" ;;
    hadolint)
      local os=${OS} arch=x86_64
      [[ ${OS} == darwin ]] && os=macos
      [[ ${ARCH} == arm64 ]] && arch=arm64
      readonly os arch
      echo "${gh}/hadolint/hadolint/releases/download/${tag}/hadolint-${os}-${arch}" ;;
    shellcheck)
      local arch=x86_64
      [[ ${ARCH} == arm64 ]] && arch=aarch64
      readonly arch
      echo "${gh}/koalaman/shellcheck/releases/download/${tag}/shellcheck-${tag}.${OS}.${arch}.tar.gz" ;;
    tflint)
      echo "${gh}/terraform-linters/tflint/releases/download/${tag}/tflint_${OS}_${ARCH}.zip" ;;
    woke)
      echo "${gh}/get-woke/woke/releases/download/${tag}/woke-${v}-${OS}-${ARCH}.tar.gz" ;;
    *)
      die "don't know how to install ${1}" ;;
  esac
}

# The installers run in a context where `set -e` is ignored, so every step checks its own result.

# no checksum verification; a checksum fetched from the same release only catches corruption.
# Pin hashes per version in versions/ if supply-chain verification is needed.
install_binary() {
  local dest=${CACHE}/tools/${1}/${2} url tmp
  readonly dest
  [[ -x ${dest}/${1} ]] && return
  url=$(binary_url "${1}" "${2}")
  readonly url
  echo "Installing ${1} ${2} from ${url}"

  tmp=$(mktemp -d) || return 1
  readonly tmp
  if ! curl -fsSL "${url}" -o "${tmp}/download"; then
    rm -rf "${tmp}"
    return 1
  fi
  case ${url} in
    *.tar.gz) tar -xzf "${tmp}/download" -C "${tmp}" ;;
    *.zip) unzip -q "${tmp}/download" -d "${tmp}" ;;
    *) mv "${tmp}/download" "${tmp}/${1}" ;;
  esac &&
    mkdir -p "${dest}" &&
    find "${tmp}" -type f -name "${1}" -exec mv {} "${dest}/${1}" \;
  rm -rf "${tmp}"
  [[ -f ${dest}/${1} ]] && chmod +x "${dest}/${1}"
}

install_pip() {
  local venv=${CACHE}/venv/${1}-${2}
  readonly venv
  # a venv breaks if the Python it was made from has gone, e.g. after an upgrade
  if [[ -x ${venv}/bin/${1} ]] && "${venv}/bin/python" -c '' 2>/dev/null; then
    return
  fi
  echo "Installing ${1} ${2} with pip"

  rm -rf "${venv}"
  if ! "${LINT_PYTHON:-python3}" -m venv "${venv}"; then
    error "couldn't create a venv; install your distro's venv package (e.g. python3-venv) or set LINT_PYTHON"
    rm -rf "${venv}"
    return 1
  fi
  if ! "${venv}/bin/python" -m pip install -q --disable-pip-version-check "${1}==${2}"; then
    rm -rf "${venv}"
    return 1
  fi
}

# The tools needed by the selected languages, without duplicates
selected_tools() {
  local lang tool seen=' '
  for lang in "${SELECTED[@]}"; do
    for tool in $(tools_for "${lang}"); do
      if [[ ${seen} != *" ${tool} "* ]]; then
        seen+="${tool} "
        echo "${tool}"
      fi
    done
  done
}

install_path() {
  if is_pip "${1}"; then
    echo "${CACHE}/venv/${1}-${2}"
  else
    echo "${CACHE}/tools/${1}/${2}"
  fi
}

# Installs everything it can; a tool that fails doesn't stop the others.
# With LINT_PRUNE=true, also deletes any other installed versions (for caches that would otherwise only grow).
install_tools() {
  local tool v path keep=' ' status=0
  platform
  for tool in $(selected_tools); do
    v=$(version "${tool}")
    keep+="$(install_path "${tool}" "${v}") "
    if is_pip "${tool}"; then
      install_pip "${tool}" "${v}"
    else
      install_binary "${tool}" "${v}"
    fi || {
      error "failed to install ${tool} ${v}"
      status=2
    }
  done
  readonly keep status

  if [[ ${LINT_PRUNE:-} == true ]]; then
    for path in "${CACHE}"/tools/*/* "${CACHE}"/venv/*; do
      if [[ -e ${path} && ${keep} != *" ${path} "* ]]; then
        echo "Pruning ${path}"
        rm -rf "${path}"
      fi
    done
  fi
  return ${status}
}

runtimes_for() {
  case ${1} in
    go) echo go ;;
    terraform) echo terraform ;;
  esac
}

need() {
  command -v "${1}" >/dev/null && return
  error "${1} not found; run 'bin/lint.sh install' or put it on the PATH"
  return 1
}

# Puts the installed version of each of a language's tools first on the PATH, falling back to whatever's
# already there. Fails if anything the language needs is missing.
setup_language() {
  local tool dir status=0
  for tool in $(tools_for "${1}"); do
    dir=$(tool_dir "${tool}")
    if [[ -d ${dir} ]]; then
      PATH=${dir}:${PATH}
    fi
    need "${tool}" || status=1
  done
  for tool in $(runtimes_for "${1}"); do
    need "${tool}" || status=1
  done
  readonly status
  return ${status}
}

# Dies on any invalid version or config input for the selected languages, before anything else happens
validate_inputs() {
  local tool
  for tool in $(selected_tools); do
    version "${tool}" >/dev/null
    config "${tool}" >/dev/null
  done
}

print_versions() {
  local tool
  for tool in $(selected_tools); do
    echo "${tool} $(version "${tool}")"
  done
}

# --- file discovery and language detection ---

collect_files() {
  local spec=("${PATHS[@]}") p f list
  for p in "${EXCLUDES[@]}"; do
    spec+=(":(exclude)${p}")
  done
  readonly spec

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "not inside a git repository"
  list=$(git ls-files -co --exclude-standard -- "${spec[@]}") || die "couldn't list files"
  readonly list
  FILES=()
  while IFS= read -r f; do
    if [[ -f ${f} ]]; then
      FILES+=("${f}")
    fi
  done <<<"${list}"
  readonly FILES
}

is_shell_script() {
  local line
  IFS= read -r line <"${1}" || true
  readonly line
  [[ ${line} =~ ^#!.*[/[:space:]](ba|da|k)?sh([[:space:]]|$) ]]
}

matches() {
  local base=${2##*/}
  readonly base
  case ${1} in
    actions)
      case ${2} in
        .github/workflows/*.yml | .github/workflows/*.yaml | */.github/workflows/*.yml | */.github/workflows/*.yaml) return 0 ;;
        .github/dependabot.yml | .github/dependabot.yaml | */.github/dependabot.yml | */.github/dependabot.yaml) return 0 ;;
      esac
      [[ ${base} == action.yml || ${base} == action.yaml ]] ;;
    docker) [[ ${base} == *Dockerfile* || ${base} == *.dockerfile || ${base} == Containerfile* ]] ;;
    go) [[ ${base} == go.mod ]] ;;
    python) [[ ${base} == *.py ]] ;;
    shell) [[ ${base} == *.sh || ${base} == *.bash ]] || { [[ ${base} != *.* ]] && is_shell_script "${2}"; } ;;
    terraform) [[ ${base} == *.tf ]] ;;
    woke) true ;;
    yaml) [[ ${base} == *.yml || ${base} == *.yaml ]] ;;
  esac
}

files_for() {
  local f
  LANG_FILES=()
  for f in "${FILES[@]}"; do
    if matches "${1}" "${f}"; then
      LANG_FILES+=("${f}")
    fi
  done
}

select_languages() {
  local lang
  SELECTED=()
  if ((${#LANGS[@]})); then
    for lang in "${LANGS[@]}"; do
      [[ " ${LANGUAGES} " == *" ${lang} "* ]] || die "unknown language '${lang}' (supported: ${LANGUAGES})"
      SELECTED+=("${lang}")
    done
  else
    for lang in ${LANGUAGES}; do
      files_for "${lang}"
      if ((${#LANG_FILES[@]})); then
        SELECTED+=("${lang}")
      fi
    done
  fi
  readonly SELECTED
}

print_json() {
  local sep='' item
  printf '['
  for item in "${@}"; do
    printf '%s"%s"' "${sep}" "${item}"
    sep=,
  done
  printf ']\n'
}

# --- linters ---
# Each runs every check for its language against LANG_FILES and returns 1 if any failed.
# zizmor and woke respect .gitignore, so without excludes (which they wouldn't know about) they're given the paths and
# find files themselves. The rest always get LANG_FILES: yamllint and flake8 would lint gitignored dirs like .venv,
# and neither hadolint nor shellcheck searches directories.

each() {
  printf '%s\0' "${LANG_FILES[@]}" | xargs -0 "${@}"
}

# For tools with no option to stay silent when they succeed: only shows their output if they fail
quiet() {
  local output rc=0
  output=$("${@}" 2>&1) || rc=${?}
  readonly output rc
  if ((rc)); then
    echo "${output}"
    return 1
  fi
}

lint_actions() {
  local rc=0 f cfg workflows=() zizmor_opts=(-q --persona auditor -c "$(config zizmor)")
  for f in "${LANG_FILES[@]}"; do
    case ${f} in
      .github/workflows/* | */.github/workflows/*) workflows+=("${f}") ;;
    esac
  done
  readonly workflows

  if ((${#workflows[@]})); then
    cfg=$(config actionlint)
    readonly cfg
    # actionlint passes scripts to shellcheck via stdin, so the rcfile's disables have to be passed as options
    SHELLCHECK_OPTS=$(sed -n 's/^[[:space:]]*disable=/-e /p' "$(config shellcheck)" | tr '\n' ' ') \
      actionlint ${cfg:+-config-file "${cfg}"} "${workflows[@]}" || rc=1
  fi

  if [[ -z ${GH_TOKEN:-} ]] && type -p gh >/dev/null; then
    GH_TOKEN=$(gh auth token 2>/dev/null) && export GH_TOKEN
  fi

  if [[ -z ${GH_TOKEN:-} ]]; then
    zizmor_opts+=(-o)
  fi
  if [[ -n ${GITHUB_ACTIONS:-} ]]; then
    zizmor_opts+=(--format github)
  fi
  readonly zizmor_opts
  if ((${#EXCLUDES[@]})); then
    quiet zizmor "${zizmor_opts[@]}" "${LANG_FILES[@]}" || rc=1
  else
    quiet zizmor "${zizmor_opts[@]}" "${PATHS[@]}" || rc=1
  fi
  readonly rc
  return ${rc}
}

lint_docker() {
  each hadolint -c "$(config hadolint)"
}

lint_go() {
  local rc=0 mod opts=(--no-config) cfg
  cfg=$(config golangci-lint)
  readonly cfg
  if [[ -n ${cfg} ]]; then
    opts=(-c "${cfg}")
  fi
  readonly opts

  for mod in "${LANG_FILES[@]}"; do
    (
      cd "$(dirname "${mod}")"
      go mod tidy -diff
    ) || rc=1
    (
      cd "$(dirname "${mod}")"
      golangci-lint run --show-stats=false "${opts[@]}" ./...
    ) || rc=1
  done
  readonly rc
  return ${rc}
}

lint_python() {
  each flake8 --config "$(config flake8)"
}

lint_shell() {
  each shellcheck --rcfile "$(config shellcheck)"
}

# Inits without a backend, keeping .terraform out of the checkout and leaving any lock file as it was found
terraform_validate() {
  local dir=${1} lock=${1}/.terraform.lock.hcl rc=0 output lockfile_opts=()
  readonly dir lock
  if [[ -f ${lock} ]]; then
    lockfile_opts=(-lockfile=readonly)
  fi
  readonly lockfile_opts

  if ! output=$(TF_DATA_DIR=$(mktemp -d "${TF_DATA_ROOT}/XXXXXX") &&
    export TF_DATA_DIR &&
    terraform -chdir="${dir}" init -backend=false -input=false "${lockfile_opts[@]}" 2>&1 &&
    terraform -chdir="${dir}" validate 2>&1); then
    echo "${output}"
    rc=1
  fi
  readonly output rc

  if ! ((${#lockfile_opts[@]})); then
    rm -f "${lock}"
  fi
  return ${rc}
}

lint_terraform() {
  local rc=0 dir f cfg
  cfg=$(config tflint)
  TF_DATA_ROOT=$(mktemp -d)
  export TF_PLUGIN_CACHE_DIR=${TF_PLUGIN_CACHE_DIR:-${CACHE}/terraform-plugins}
  readonly cfg TF_DATA_ROOT TF_PLUGIN_CACHE_DIR
  mkdir -p "${TF_PLUGIN_CACHE_DIR}"

  quiet tflint --init -c "${cfg}" || rc=1
  while IFS= read -r dir; do
    terraform fmt -check -diff "${dir}" || rc=1
    terraform_validate "${dir}" || rc=1
    tflint --chdir="${dir}" -c "${cfg}" || rc=1
  done < <(for f in "${LANG_FILES[@]}"; do dirname "${f}"; done | sort -u)
  readonly rc

  rm -rf "${TF_DATA_ROOT}"
  return ${rc}
}

lint_woke() {
  local cfg opts=(--exit-1-on-failure)
  cfg=$(config woke)
  readonly cfg
  if [[ -n ${cfg} ]]; then
    opts+=(-c "${cfg}")
  fi
  if [[ -n ${GITHUB_ACTIONS:-} ]]; then
    opts+=(-o github-actions)
  fi
  readonly opts
  if ((${#EXCLUDES[@]})); then
    quiet each woke "${opts[@]}"
  else
    quiet woke "${opts[@]}" "${PATHS[@]}"
  fi
}

lint_yaml() {
  each yamllint -s -c "$(config yamllint)"
}

# Runs every language even if others fail. A setup failure (status 2) outranks lint failures (status 1).
run_linters() {
  local lang status=0
  for lang in "${SELECTED[@]}"; do
    files_for "${lang}"
    if ! ((${#LANG_FILES[@]})); then
      warn "no ${lang} files found"
      continue
    fi

    group "${lang}"
    if ! setup_language "${lang}"; then
      error "skipping ${lang} checks; it couldn't be set up"
      status=2
    elif ! "lint_${lang}"; then
      ((status)) || status=1
    fi
    endgroup
  done
  readonly status
  return ${status}
}

# --- main ---

usage() {
  sed -n '3,/^$/s/^# \{0,1\}//p' "${BASH_SOURCE[0]}"
  exit "${1:-0}"
}

cmd=run
case ${1:-} in
  detect | install | run | version | versions)
    cmd=${1}
    shift
    ;;
esac
readonly cmd

if [[ ${cmd} == version ]]; then
  [[ ${#} -eq 1 ]] || usage 2
  version "${1}"
  exit
fi

# also accepts detect's JSON output
LINT_LANGUAGES=${LINT_LANGUAGES:-}
readonly LINT_LANGUAGES
split LANGS "${LINT_LANGUAGES//[\[\]\"]/}"
split EXCLUDES "${LINT_EXCLUDE:-}"
split PATHS "${LINT_PATHS:-}"
while ((${#})); do
  case ${1} in
    --languages)
      split LANGS "${2:?--languages needs a value}"
      shift 2
      ;;
    --exclude)
      EXCLUDES+=("${2:?--exclude needs a value}")
      shift 2
      ;;
    -h | --help) usage ;;
    -*) die "unknown option ${1}" ;;
    *)
      PATHS+=("${1}")
      shift
      ;;
  esac
done
readonly LANGS EXCLUDES
if ! ((${#PATHS[@]})); then
  PATHS=(.)
fi
readonly PATHS

collect_files
select_languages

if [[ ${cmd} != detect ]]; then
  validate_inputs
fi

case ${cmd} in
  detect) print_json "${SELECTED[@]}" ;;
  install) install_tools ;;
  run) run_linters ;;
  versions) print_versions ;;
esac
