#!/usr/bin/env bash

catch() {
  {
    IFS=$'\n' read -r -d '' "${1}";
    IFS=$'\n' read -r -d '' "${2}";
    (IFS=$'\n' read -r -d '' _ERRNO_; return "${_ERRNO_}");
  } < <((printf '\0%s\0%d\0' "$( ( ( ( { shift 2; "${@}"; echo "${?}" 1>&3-; } | tr -d '\0' 1>&4-) 4>&2- 2>&1- | tr -d '\0' 1>&4-) 3>&1- | exit "$(cat)" ) 4>&1- )" "${?}" 1>&2 ) 2>&1 )
}

if [[ "$(uname)" == 'Darwin' ]]; then
  if ! type -p brew; then
    echo "Homebrew not found; installing..."
    export NONINTERACTIVE=1
    /usr/bin/env bash -c "$(curl -fgsLS https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  export HOMEBREW_NO_AUTO_UPDATE=1
  eval "$(/opt/homebrew/bin/brew shellenv)"

  {
    echo "${HOMEBREW_PREFIX}/bin"
    echo "${HOMEBREW_PREFIX}/sbin"
  } >>"${GITHUB_PATH}"

  if ! type -p actionlint; then
    echo "actionlint not found; installing..."
    brew install actionlint
  fi
  if ! type -p python3; then
    echo "python3 not found; installing..."
    brew install python3
  fi
  if ! type -p shellcheck; then
    echo "shellcheck not found; installing..."
    brew install shellcheck
  fi
  if ! type -p yamllint; then
    echo "yamllint not found; installing..."
    brew install yamllint
  fi

  # shellcheck disable=SC2155
  declare -r python_minor_version="$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")"
else
  # shellcheck disable=SC2155
  declare -r python_minor_version="$(python3 -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")"

  sudo apt-get update
  sudo apt-get install -y "python${python_minor_version}-venv" shellcheck
fi

echo "Python version is ${python_minor_version}"

if ! type -p pip && ! type -p pip3 &>/dev/null; then
  echo "pip is not installed!"
  declare -r url="https://bootstrap.pypa.io/${python_minor_version}/get-pip.py"
  if curl -fgsLI -o /dev/null "${url}"; then
    echo "Found pip version on pypa.io matching python version; downloading it ..."
    curl -fgsLS "${url}" -o get-pip.py
  else
    echo "Could not find pip version on pypa.io matching python version; downloading latest ..."
    curl -fgsLS 'https://bootstrap.pypa.io/pip/get-pip.py' -o get-pip.py
  fi

  echo "Installing pip ..."
  python3 get-pip.py --break-system-packages
else
  declare pip_version stderr
  catch pip_version stderr .github/pip-update-needed.py
  declare -r update_needed=$?
  readonly pip_version

  if [[ -n "${stderr}" ]]; then
    echo "Error: ${stderr}"
  fi

  if [[ ${update_needed} -eq 0 ]]; then
    echo "pip version is ${pip_version}; need at least 23.1. Upgrading ..."
    python3 -m pip install --upgrade pip
  else
    echo "pip version is ${pip_version}"
  fi
fi

python3 -m pip install flake8 pipx pyflakes --break-system-packages
