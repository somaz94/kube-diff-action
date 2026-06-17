#!/usr/bin/env bash
set -euo pipefail

VERSION="${VERSION:-latest}"

# Determine OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "${ARCH}" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  arm64)   ARCH="arm64" ;;
  *)       echo "::error::Unsupported architecture: ${ARCH}"; exit 1 ;;
esac

case "${OS}" in
  linux)  OS="linux" ;;
  darwin) OS="darwin" ;;
  *)      echo "::error::Unsupported OS: ${OS}"; exit 1 ;;
esac

# Authenticated GitHub API calls get 5000 requests/hour vs 60/hour per source
# IP; on shared Actions runners the unauthenticated pool is frequently exhausted
# (403/429), so pass a token when one is available.
AUTH_HEADER=()
[[ -n "${GITHUB_TOKEN:-}" ]] && AUTH_HEADER=(-H "Authorization: Bearer ${GITHUB_TOKEN}")

# Run curl with bounded retry + exponential backoff. Rides over the transient
# 403/429/5xx and CDN hiccups that intermittently flake the install step.
curl_retry() {
  local attempt=1 max=5 delay=2
  while true; do
    curl -fsSL "$@" && return 0
    (( attempt >= max )) && return 1
    echo "curl failed (attempt ${attempt}/${max}); retrying in ${delay}s..." >&2
    sleep "${delay}"
    attempt=$(( attempt + 1 ))
    delay=$(( delay * 2 ))
  done
}

# Resolve version
if [[ "${VERSION}" == "latest" ]]; then
  echo "::group::Resolving latest kube-diff version"
  api_response=$(curl_retry ${AUTH_HEADER[@]+"${AUTH_HEADER[@]}"} \
    https://api.github.com/repos/somaz94/kube-diff/releases/latest) || {
    echo "::error::Failed to query GitHub API for the latest version"
    exit 1
  }
  VERSION=$(printf '%s' "${api_response}" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
  if [[ -z "${VERSION}" ]]; then
    echo "::error::Failed to resolve latest version"
    exit 1
  fi
  echo "Resolved version: ${VERSION}"
  echo "::endgroup::"
fi

# Strip leading 'v' for filename
VERSION_NUM="${VERSION#v}"

FILENAME="kube-diff_${VERSION_NUM}_${OS}_${ARCH}.tar.gz"
URL="https://github.com/somaz94/kube-diff/releases/download/${VERSION}/${FILENAME}"

echo "::group::Installing kube-diff ${VERSION} (${OS}/${ARCH})"
echo "Downloading: ${URL}"

TMPDIR=$(mktemp -d)
trap 'rm -rf "${TMPDIR}"' EXIT

if ! curl_retry -o "${TMPDIR}/kube-diff.tar.gz" "${URL}"; then
  echo "::error::Failed to download kube-diff from ${URL}"
  exit 1
fi

tar -xzf "${TMPDIR}/kube-diff.tar.gz" -C "${TMPDIR}"

if [[ ! -f "${TMPDIR}/kube-diff" ]]; then
  echo "::error::kube-diff binary not found in archive"
  exit 1
fi

chmod +x "${TMPDIR}/kube-diff"
if [[ -w /usr/local/bin ]]; then
  mv "${TMPDIR}/kube-diff" /usr/local/bin/kube-diff
else
  sudo mv "${TMPDIR}/kube-diff" /usr/local/bin/kube-diff
fi

echo "Installed: $(kube-diff version)"
echo "::endgroup::"
