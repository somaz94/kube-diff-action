#!/usr/bin/env bash
# Runs scripts/run.sh and scripts/comment.sh against stub kube-diff and gh binaries.
# fixtures/*.txt are real kube-diff reports: two changed resources (one cluster-scoped),
# plus one new, one unchanged and one deleted.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURES="${ROOT}/tests/fixtures"
WORK=$(mktemp -d)
trap 'rm -rf "${WORK}"' EXIT
mkdir -p "${WORK}/bin"

cat > "${WORK}/bin/kube-diff" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "${STUB_ARGS}"
printf '%s' "${STUB_STDOUT}"
printf '%s' "${STUB_STDERR}" >&2
exit "${STUB_EXIT}"
EOF

cat > "${WORK}/bin/gh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${STUB_CALLS}"
for arg in "$@"; do
  case "${arg}" in
    --jq) printf '%s\n' "${STUB_EXISTING_ID}"; exit 0 ;;
    body=*) printf '%s' "${arg#body=}" > "${STUB_BODY}" ;;
  esac
done
EOF
chmod +x "${WORK}/bin/kube-diff" "${WORK}/bin/gh"

FAILURES=0
check() {
  if "${@:2}"; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    FAILURES=$((FAILURES + 1))
  fi
}
contains() { [[ "$1" == *"$2"* ]]; }
lacks() { [[ "$1" != *"$2"* ]]; }
occurrences() { grep -cF -- "$2" <<< "$1" || true; }

# usage: run_diff <kube-diff exit> <stdout> <stderr> [VAR=value...]
run_diff() {
  : > "${WORK}/github_output"
  set +e
  env PATH="${WORK}/bin:${PATH}" STUB_ARGS="${WORK}/args" \
    STUB_EXIT="$1" STUB_STDOUT="$2" STUB_STDERR="$3" GITHUB_OUTPUT="${WORK}/github_output" \
    INPUT_SOURCE=file INPUT_PATH=manifests INPUT_VALUES= INPUT_RELEASE= INPUT_NAMESPACE= \
    INPUT_KIND= INPUT_SELECTOR= INPUT_OUTPUT=plain INPUT_SUMMARY_ONLY=false \
    "${@:4}" bash "${ROOT}/scripts/run.sh" > "${WORK}/run.log" 2>&1
  RUN_RC=$?
  set -e
}
output() { grep -m1 "^$1=" "${WORK}/github_output" | cut -d= -f2-; }
result_output() { awk '/^KUBE_DIFF_EOF$/{f=0} f; /^result<<KUBE_DIFF_EOF$/{f=1}' "${WORK}/github_output"; }

# usage: render <fixture> [VAR=value...]; the posted comment lands in BODY
render() {
  : > "${WORK}/calls"
  : > "${WORK}/body"
  env PATH="${WORK}/bin:${PATH}" STUB_CALLS="${WORK}/calls" STUB_BODY="${WORK}/body" STUB_EXISTING_ID= \
    GITHUB_EVENT_NUMBER=7 GITHUB_REPOSITORY=octo/repo HAS_CHANGES=true \
    DIFF_RESULT="$(cat "${FIXTURES}/$1.txt")" INPUT_OUTPUT="$1" INPUT_SUMMARY_ONLY=false \
    "${@:2}" bash "${ROOT}/scripts/comment.sh" > /dev/null
  BODY=$(cat "${WORK}/body")
  CALLS=$(cat "${WORK}/calls")
}

echo "# run.sh"

run_diff 0 "$(cat "${FIXTURES}/plain.txt")" ""
check "no drift: step succeeds" test "${RUN_RC}" -eq 0
check "no drift: exit-code=0" test "$(output exit-code)" = 0
check "no drift: has-changes=false" test "$(output has-changes)" = false

run_diff 1 "drift report" "Warning: deprecated API"
check "drift: step succeeds" test "${RUN_RC}" -eq 0
check "drift: exit-code=1" test "$(output exit-code)" = 1
check "drift: has-changes=true" test "$(output has-changes)" = true
check "drift: result holds stdout only" test "$(result_output)" = "drift report"

run_diff 1 "" "Error: failed to load resources: boom"
check "error: step fails" test "${RUN_RC}" -eq 1
check "error: exit-code=2" test "$(output exit-code)" = 2
check "error: has-changes=false" test "$(output has-changes)" = false
check "error: annotation carries the cause" grep -qF '::error::kube-diff failed (exit 1): failed to load resources: boom' "${WORK}/run.log"

run_diff 127 "" "kube-diff: command not found"
check "unexpected exit: step fails" test "${RUN_RC}" -eq 1
check "unexpected exit: exit-code=2" test "$(output exit-code)" = 2

run_diff 1 "drift report" "" INPUT_EXIT_CODE=true
check "exit-code input: reported exit-code=0" test "$(output exit-code)" = 0
check "exit-code input: has-changes still true" test "$(output has-changes)" = true
check "exit-code input: not forwarded to kube-diff" lacks "$(cat "${WORK}/args")" "--exit-code"

echo "# comment.sh"

render markdown
check "markdown: report heading replaced by title" lacks "${BODY}" "## kube-diff Report"
check "markdown: status table kept" contains "${BODY}" "| ⚪ OK | Service/web | default |"
check "markdown: namespaced diff folded" contains "${BODY}" "<summary>ConfigMap/app-config</summary>"
check "markdown: cluster-scoped diff folded" contains "${BODY}" "<summary>ClusterRole/reader</summary>"
check "markdown: diff body kept" contains "${BODY}" "+        - watch"
check "markdown: details balanced" test "$(occurrences "${BODY}" "<details>")" -eq 2 -a "$(occurrences "${BODY}" "</details>")" -eq 2

render plain
check "plain: cluster-scoped resource kept" contains "${BODY}" "<summary>~ CHANGED ClusterRole/reader</summary>"
check "plain: new resource is a bullet" contains "${BODY}" "- * NEW    Deployment/web (namespace: default)"
check "plain: no diff attributed to the new resource" lacks "${BODY}" "<summary>* NEW"
check "plain: unchanged resource kept" contains "${BODY}" "-   OK     Service/web (namespace: default)"
check "plain: summary line kept" contains "${BODY}" "**Summary: 5 resources"
check "plain: footer separated from summary" contains "${BODY}" $'unchanged**\n\n---'

render color
check "color: ANSI escapes stripped" lacks "${BODY}" $'\033'
check "color: new resource is a bullet" contains "${BODY}" "- ★ NEW    Deployment/web (namespace: default)"
check "color: unchanged resource kept" contains "${BODY}" "- ✓ OK     Service/web (namespace: default)"
check "color: cluster-scoped resource kept" contains "${BODY}" "<summary>~ CHANGED ClusterRole/reader</summary>"

render json
check "json: fenced as json" contains "${BODY}" '```json'
check "json: payload kept" contains "${BODY}" '"kind": "ClusterRole"'

render table
check "table: fenced as text" contains "${BODY}" '```text'
check "table: rows kept" contains "${BODY}" "ClusterRole"

render summary INPUT_OUTPUT=markdown INPUT_SUMMARY_ONLY=true
check "summary-only: summary line kept" contains "${BODY}" "**Summary: 5 resources"
check "summary-only: ANSI escapes stripped" lacks "${BODY}" $'\033'

HUGE=$(printf '~ CHANGED ConfigMap/huge (namespace: default)\n'; for i in $(seq 1 3000); do printf '+  line-%s padding padding padding\n' "${i}"; done; printf '\nSummary: 1 resources — 1 changed\n')
render plain DIFF_RESULT="${HUGE}" GITHUB_RUN_ID=99
check "oversize: body fits GitHub's limit" test "${#BODY}" -lt 65536
check "oversize: summary kept" contains "${BODY}" "Summary: 1 resources"
check "oversize: links the run" contains "${BODY}" "(https://github.com/octo/repo/actions/runs/99)"

render plain HAS_CHANGES=false
check "no drift: title" contains "${BODY}" "No Cluster Drift"

render plain
check "upsert: creates when no marker comment exists" contains "${CALLS}" "repos/octo/repo/issues/7/comments -f body="

render plain STUB_EXISTING_ID=42
check "upsert: patches the marker comment" contains "${CALLS}" "repos/octo/repo/issues/comments/42 -X PATCH"

render plain GITHUB_EVENT_NUMBER= GITHUB_EVENT_PATH=/dev/null
check "no PR number: skips without calling gh" test -z "${CALLS}"

echo
if [[ ${FAILURES} -gt 0 ]]; then
  echo "${FAILURES} check(s) failed"
  exit 1
fi
echo "all checks passed"
