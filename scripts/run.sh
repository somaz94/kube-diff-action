#!/usr/bin/env bash
set -euo pipefail

# Validate source type
case "${INPUT_SOURCE}" in
  file|helm|kustomize) ;;
  *) echo "::error::Invalid source type '${INPUT_SOURCE}'. Must be: file, helm, or kustomize"; exit 1 ;;
esac

# Build command as array (safer than eval)
CMD=(kube-diff "${INPUT_SOURCE}" "${INPUT_PATH}")

# Add helm-specific flags
if [[ "${INPUT_SOURCE}" == "helm" ]]; then
  if [[ -n "${INPUT_VALUES}" ]]; then
    IFS=',' read -ra VALUES <<< "${INPUT_VALUES}"
    for v in "${VALUES[@]}"; do
      trimmed=$(echo "${v}" | xargs)
      CMD+=(-f "${trimmed}")
    done
  fi
  if [[ -n "${INPUT_RELEASE}" ]]; then
    CMD+=(-r "${INPUT_RELEASE}")
  fi
fi

# Add global flags
if [[ -n "${INPUT_NAMESPACE}" ]]; then
  CMD+=(-n "${INPUT_NAMESPACE}")
fi

if [[ -n "${INPUT_KIND}" ]]; then
  CMD+=(-k "${INPUT_KIND}")
fi

if [[ -n "${INPUT_SELECTOR}" ]]; then
  CMD+=(-l "${INPUT_SELECTOR}")
fi

if [[ -n "${INPUT_OUTPUT}" ]]; then
  CMD+=(-o "${INPUT_OUTPUT}")
fi

if [[ "${INPUT_SUMMARY_ONLY}" == "true" ]]; then
  CMD+=(-s)
fi

echo "::group::Running kube-diff"
echo "Command: ${CMD[*]}"

# Run kube-diff and capture output
set +e
RESULT=$("${CMD[@]}" 2>&1)
EXIT_CODE=$?
set -e

echo "${RESULT}"
echo "::endgroup::"

# Set outputs
{
  echo "exit-code=${EXIT_CODE}"
  if [[ ${EXIT_CODE} -eq 1 ]]; then
    echo "has-changes=true"
  else
    echo "has-changes=false"
  fi
} >> "${GITHUB_OUTPUT}"

# Handle multiline result output
{
  echo "result<<KUBE_DIFF_EOF"
  echo "${RESULT}"
  echo "KUBE_DIFF_EOF"
} >> "${GITHUB_OUTPUT}"

# Exit code 0 (no changes) and 1 (changes detected) are both success for the action
# Only exit code 2 (error) should fail the action
if [[ ${EXIT_CODE} -eq 2 ]]; then
  echo "::error::kube-diff encountered an error"
  exit 1
fi
