# composite-lint

All-in-one opinionated selection of linters &amp; config.

## Usage

```yaml
- uses: actions/checkout@v7
  with:
    persist-credentials: false

- uses: ReadOnlyTech/composite-lint@v1
  with:
    # optional; detected from the files present otherwise
    languages: python, shell, yaml
```

Only the tools needed for the selected languages are installed. Every tool's version can be overridden with
`<tool>-version` or `<tool>-version-file`, and its config with `<tool>-config`; anything unset uses what's bundled in
[`versions/`](versions) and [`configs/`](configs). See [`action.yml`](action.yml) for all inputs.

Linux runners only, both GitHub-hosted and self-hosted.

The linters, Go's module/build caches, golangci-lint's analysis cache, and Terraform providers are kept in the Actions
cache, which counts toward the repo's cache quota. Set `cache: false` to turn that off.

## Running locally

```sh
bin/lint.sh install   # installs pinned tools into ~/.cache/composite-lint
bin/lint.sh           # lints the current repo
bin/lint.sh --languages shell --exclude tests/fail path/to/dir
```

Settings come from the same `LINT_*` environment variables the action uses; see `bin/lint.sh --help`.

## Development

```sh
bin/lint.sh --exclude tests/fail   # lint this repo with itself
tests/run.sh                       # check tests/pass lints clean and each tests/fail case fails as expected
```

Each `tests/fail/<language>/<case>/` holds the files to lint plus an `expect` file containing a regex that must
appear in the output.

## Supported Languages / Ecosystems

### Docker

Using `hadolint` and `trivy`.

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
