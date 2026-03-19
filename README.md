# kube-diff-action

[![CI](https://github.com/somaz94/kube-diff-action/actions/workflows/ci.yml/badge.svg)](https://github.com/somaz94/kube-diff-action/actions/workflows/ci.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](LICENSE)
[![Latest Tag](https://img.shields.io/github/v/tag/somaz94/kube-diff-action)](https://github.com/somaz94/kube-diff-action/tags)
[![Top Language](https://img.shields.io/github/languages/top/somaz94/kube-diff-action)](https://github.com/somaz94/kube-diff-action)
[![GitHub Marketplace](https://img.shields.io/badge/Marketplace-Kube%20Diff%20Action-blue?logo=github)](https://github.com/marketplace/actions/kube-diff-action)

A GitHub Action that compares local Kubernetes manifests against live cluster state using [kube-diff](https://github.com/somaz94/kube-diff), and optionally posts the diff as a PR comment.

<br/>

## Features

- Compare **plain YAML**, **Helm charts**, or **Kustomize overlays** against your cluster
- Auto-post diff results as **PR comments** (updates existing comment on re-run)
- Multiple output formats: `color`, `plain`, `json`, `markdown`, `table`
- Ignore specific fields in diff with `ignore-field`
- Configurable context lines, exit code behavior, and diff strategy
- Compare against live state or `last-applied-configuration` annotation
- Filter by **namespace**, **kind**, or **label selector**
- Detects drift: changed, new, deleted, and unchanged resources

<br/>

## Quick Start

```yaml
- name: Check for drift
  uses: somaz94/kube-diff-action@v1
  with:
    source: file
    path: ./manifests/
    namespace: production
```

<br/>

## Usage

### File mode

```yaml
- uses: somaz94/kube-diff-action@v1
  with:
    source: file
    path: ./manifests/
    namespace: production
    kind: Deployment,Service
```

### Helm mode

```yaml
- uses: somaz94/kube-diff-action@v1
  with:
    source: helm
    path: ./my-chart/
    values: values-prod.yaml
    release: my-release
    namespace: production
```

### Kustomize mode

```yaml
- uses: somaz94/kube-diff-action@v1
  with:
    source: kustomize
    path: ./overlays/production/
```

### PR comment with drift detection

```yaml
name: Drift Check
on:
  pull_request:
    paths:
      - 'manifests/**'

jobs:
  drift-check:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write
    steps:
      - uses: actions/checkout@v4

      - name: Setup kubeconfig
        # Configure your cluster access here
        run: echo "${{ secrets.KUBECONFIG }}" > /tmp/kubeconfig

      - name: Check drift
        id: diff
        uses: somaz94/kube-diff-action@v1
        with:
          source: file
          path: ./manifests/
          namespace: production
          comment: 'true'
        env:
          KUBECONFIG: /tmp/kubeconfig

      - name: Fail if drift detected
        if: steps.diff.outputs.has-changes == 'true'
        run: |
          echo "Drift detected!"
          exit 1
```

### Ignore fields and custom context

```yaml
- uses: somaz94/kube-diff-action@v1
  with:
    source: file
    path: ./manifests/
    namespace: production
    ignore-field: metadata.annotations.checksum/config,spec.replicas
    context-lines: '5'
    exit-code: 'true'
```

### Compare against last-applied-configuration

```yaml
- uses: somaz94/kube-diff-action@v1
  with:
    source: file
    path: ./manifests/
    namespace: production
    diff-strategy: last-applied
```

### JSON output for downstream processing

```yaml
- name: Get drift report
  id: diff
  uses: somaz94/kube-diff-action@v1
  with:
    source: file
    path: ./manifests/
    output: json
    comment: 'false'

- name: Process result
  run: echo '${{ steps.diff.outputs.result }}' | jq '.resources[] | select(.status == "changed")'
```

<br/>

## Inputs

| Input | Description | Required | Default |
|-------|-------------|----------|---------|
| `source` | Source type: `file`, `helm`, or `kustomize` | **Yes** | |
| `path` | Path to manifests, chart, or overlay | **Yes** | |
| `values` | Helm values files (comma-separated) | No | |
| `release` | Helm release name | No | `release` |
| `namespace` | Filter by namespace | No | |
| `kind` | Filter by resource kind (comma-separated) | No | |
| `selector` | Label selector (e.g., `app=nginx,env=prod`) | No | |
| `output` | Output format: `color`, `plain`, `json`, `markdown`, `table` | No | `markdown` |
| `summary-only` | Show summary only | No | `false` |
| `ignore-field` | Field paths to ignore in diff (comma-separated, dot notation) | No | |
| `context-lines` | Number of context lines in diff output | No | `3` |
| `exit-code` | Always exit 0 even when changes are detected | No | `false` |
| `diff-strategy` | Comparison strategy: `live` or `last-applied` | No | `live` |
| `comment` | Post result as PR comment | No | `true` |
| `version` | kube-diff version to install | No | `latest` |
| `token` | GitHub token for PR comments | No | `${{ github.token }}` |

<br/>

## Outputs

| Output | Description |
|--------|-------------|
| `result` | Full diff output text |
| `exit-code` | `0` = no changes, `1` = changes detected |
| `has-changes` | `true` if drift was detected, `false` otherwise |

<br/>

## Exit Codes

The action **does not fail** when drift is detected (exit code 1). Only errors (exit code 2) cause failure. Use `has-changes` output to control your workflow:

```yaml
- name: Fail on drift
  if: steps.diff.outputs.has-changes == 'true'
  run: exit 1
```

<br/>

## License

This project is licensed under the Apache License 2.0 — see the [LICENSE](LICENSE) file for details.
