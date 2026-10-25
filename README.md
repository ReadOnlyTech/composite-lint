# composite-lint

All-in-one opinionated selection of linters &amp; config.

(Tested with Linux runners only, both GitHub-hosted and self-hosted.)

## Usage

See [`action.yml`](action.yml) for all inputs.

```yaml
- name: Check out repo
  uses: actions/checkout@v7
  with:
    persist-credentials: false

- name: Run linting (strict, autodetect)
  uses: ReadOnlyTech/composite-lint@v0

- name: Run linting (custom)
  uses: ReadOnlyTech/composite-lint@v0
  with:
    cache: false
    paths: src
    exclude: 'src/build/*.py,src/scripts/*.sh'
    github-token: ${{ secrets.MY_GH_TOKEN }}
    languages: python,shell
    python-version-file: src/main/python/.python-version
    shellcheck-config: .shellcheckrc
    shellcheck-version: 0.9
```

Only the tools needed for the selected `languages` (defaulting to auto-detection) are installed. Every language /
tool version can be overridden with `<tool>-version` or `<tool>-version-file`, and its config with `<tool>-config`;
anything unset uses what's bundled in[`versions/`](versions) and [`configs/`](configs).  As a general rule, these
default versions are "latest stable" and the default configs are "very strict".

The linters, Go's module/build caches, golangci-lint's analysis cache, and Terraform providers are kept in the Actions
cache, and count toward your repo's cache quota. Set `cache: false` to turn that off.

## Supported Languages / Ecosystems

### Docker

Using `hadolint`.

### GitHub Actions

Using `actionlint`, `yamllint`, and `zizmor`.

### Go

Using `golangci`.

### Python

Using `flake8`.

### Shell

Using `shellcheck`.

### Terraform

Using `terraform` and `tflint`.

### YAML

Using `yamllint`.

## Other Checks

- `woke`

## Running Locally

```sh
# installs pinned tools into ~/.cache/composite-lint
bin/lint.sh install

# lints the current dir (`.`)
bin/lint.sh

$ lints the target language, excluding one dir and targeting another
bin/lint.sh --languages shell --exclude tests/fail path/to/dir
```

Settings come from the same `LINT_*` environment variables the action uses; see `bin/lint.sh --help`.

## Development

```sh
# lint this repo with itself
bin/lint.sh --exclude tests/fail

# check tests/pass lints clean and each tests/fail case fails as expected
tests/run.sh
```

Each `tests/fail/<language>/<case>/` holds the files to lint, plus an `expect` file containing a regex that must
appear in the output.
