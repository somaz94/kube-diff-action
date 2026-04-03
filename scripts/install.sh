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

# Resolve version
if [[ "${VERSION}" == "latest" ]]; then
  echo "::group::Resolving latest kube-diff version"
  VERSION=$(curl -sL https://api.github.com/repos/somaz94/kube-diff/releases/latest | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
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

if ! curl -sL -o "${TMPDIR}/kube-diff.tar.gz" "${URL}"; then
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
