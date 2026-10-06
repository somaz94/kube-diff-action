#!/usr/bin/env bash
set -euo pipefail

case "${INPUT_SOURCE}" in
  file|helm|kustomize) ;;
  *) echo "::error::Invalid source type '${INPUT_SOURCE}'. Must be: file, helm, or kustomize"; exit 1 ;;
esac

# Build command as array (safer than eval)
CMD=(kube-diff "${INPUT_SOURCE}" "${INPUT_PATH}")

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

if [[ -n "${INPUT_NAMESPACE}" ]]; then
  CMD+=(-n "${INPUT_NAMESPACE}")
fi

if [[ -n "${INPUT_KIND}" ]]; then
  CMD+=(-k "${INPUT_KIND}")
fi

if [[ -n "${INPUT_NAME:-}" ]]; then
  IFS=',' read -ra NAMES <<< "${INPUT_NAME}"
  for n in "${NAMES[@]}"; do
    trimmed=$(echo "${n}" | xargs)
    CMD+=(-N "${trimmed}")
  done
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

if [[ -n "${INPUT_IGNORE_FIELD:-}" ]]; then
  IFS=',' read -ra FIELDS <<< "${INPUT_IGNORE_FIELD}"
  for f in "${FIELDS[@]}"; do
    trimmed=$(echo "${f}" | xargs)
    CMD+=(--ignore-field "${trimmed}")
  done
fi

if [[ -n "${INPUT_CONTEXT_LINES:-}" ]]; then
  CMD+=(-C "${INPUT_CONTEXT_LINES}")
fi

if [[ -n "${INPUT_DIFF_STRATEGY:-}" ]]; then
  CMD+=(--diff-strategy "${INPUT_DIFF_STRATEGY}")
fi

echo "::group::Running kube-diff"
echo "Command: ${CMD[*]}"

STDERR_FILE=$(mktemp)
trap 'rm -f "${STDERR_FILE}"' EXIT

set +e
RESULT=$("${CMD[@]}" 2>"${STDERR_FILE}")
KUBE_DIFF_EXIT=$?
set -e

echo "${RESULT}"
cat "${STDERR_FILE}" >&2
echo "::endgroup::"

# kube-diff exits 2 on error since v0.5.3; older releases exit 1 for errors too, and only their "Error: " line tells them from drift.
ERROR_LINE=$(grep -m1 '^Error: ' "${STDERR_FILE}" || true)
if [[ ${KUBE_DIFF_EXIT} -eq 0 ]]; then
  EXIT_CODE=0
elif [[ ${KUBE_DIFF_EXIT} -eq 1 && -z "${ERROR_LINE}" ]]; then
  EXIT_CODE=1
else
  EXIT_CODE=2
fi

HAS_CHANGES=false
if [[ ${EXIT_CODE} -eq 1 ]]; then
  HAS_CHANGES=true
fi

# kube-diff's own --exit-code would hide drift from has-changes, so the input only masks the reported code.
REPORTED_EXIT_CODE=${EXIT_CODE}
if [[ "${HAS_CHANGES}" == "true" && "${INPUT_EXIT_CODE:-false}" == "true" ]]; then
  REPORTED_EXIT_CODE=0
fi

{
  echo "exit-code=${REPORTED_EXIT_CODE}"
  echo "has-changes=${HAS_CHANGES}"
} >> "${GITHUB_OUTPUT}"

# Handle multiline result output
{
  echo "result<<KUBE_DIFF_EOF"
  echo "${RESULT}"
  echo "KUBE_DIFF_EOF"
} >> "${GITHUB_OUTPUT}"

if [[ ${EXIT_CODE} -eq 2 ]]; then
  echo "::error::kube-diff failed (exit ${KUBE_DIFF_EXIT}): ${ERROR_LINE#Error: }"
  exit 1
fi
