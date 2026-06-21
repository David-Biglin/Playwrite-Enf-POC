#!/usr/bin/env bash
set -euo pipefail
umask 022

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$BASE_DIR"

export PLAYWRIGHT_UID="${PLAYWRIGHT_UID:-$(id -u)}"
export PLAYWRIGHT_GID="${PLAYWRIGHT_GID:-$(id -g)}"
export PLAYWRIGHT_BASE_URL="${PLAYWRIGHT_BASE_URL:-https://example.com}"
export PLAYWRIGHT_WORKERS="${PLAYWRIGHT_WORKERS:-2}"
export REPORT_HISTORY_LIMIT="${REPORT_HISTORY_LIMIT:-10}"

timestamp="$(date '+%Y%m%d-%H%M%S')"
run_dir="reports/history/${timestamp}"
latest_dir="reports/latest"
state_dir=".state"
lock_hash_file="${state_dir}/package-lock.sha256"

mkdir -p "$run_dir" "$latest_dir" test-results playwright-report "$state_dir"
chmod 755 reports reports/history "$latest_dir" test-results playwright-report "$state_dir" 2>/dev/null || true

log() {
  printf '[playwright-regression] %s\n' "$*"
}

fail() {
  log "$*"
  exit 1
}

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    return 1
  fi
}

prune_history() {
  local limit="${1}"
  local history_root="reports/history"
  local count=0
  local entry

  case "$limit" in
    ''|*[!0-9]*)
      fail "REPORT_HISTORY_LIMIT must be a non-negative integer."
      ;;
  esac

  [ "$limit" -eq 0 ] && return 0

  while IFS= read -r entry; do
    count=$((count + 1))
    if [ "$count" -gt "$limit" ]; then
      rm -rf "${history_root}/${entry}"
    fi
  done <<EOF
$(find "$history_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r)
EOF
}

if docker compose version >/dev/null 2>&1; then
  compose_cmd=(docker compose)
elif command -v docker-compose >/dev/null 2>&1; then
  compose_cmd=(docker-compose)
else
  fail "Neither 'docker compose' nor 'docker-compose' is available."
fi

if ! docker info >/dev/null 2>&1; then
  fail "Docker is installed but the daemon is not reachable."
fi

if ! "${compose_cmd[@]}" ps --status running playwright >/dev/null 2>&1; then
  log "Starting Playwright services..."
  "${compose_cmd[@]}" up -d
fi

current_lock_hash=""
stored_lock_hash=""

if [ -f package-lock.json ]; then
  current_lock_hash="$(hash_file package-lock.json)" || fail "A SHA-256 utility is required to validate package-lock.json."
fi

if [ -f "${lock_hash_file}" ]; then
  stored_lock_hash="$(tr -d '\n' < "${lock_hash_file}")"
fi

if [ ! -d node_modules/@playwright/test ] || [ "${current_lock_hash}" != "${stored_lock_hash}" ]; then
  log "Installing Playwright dependencies..."
  if [ -f package-lock.json ]; then
    "${compose_cmd[@]}" exec -T playwright npm ci --no-fund --no-audit
    printf '%s\n' "${current_lock_hash}" > "${lock_hash_file}"
  else
    "${compose_cmd[@]}" exec -T playwright npm install --no-fund --no-audit
  fi
fi

log "Running Playwright regression suite..."
set +e
"${compose_cmd[@]}" exec -T \
  -e PLAYWRIGHT_BASE_URL="${PLAYWRIGHT_BASE_URL}" \
  -e PLAYWRIGHT_WORKERS="${PLAYWRIGHT_WORKERS}" \
  playwright \
  npx playwright test
test_exit_code=$?
set -e

if [ -d playwright-report ]; then
  rm -rf "${run_dir}/html-report"
  mkdir -p "${run_dir}/html-report"
  cp -R playwright-report/. "${run_dir}/html-report/"

  mkdir -p "${latest_dir}"
  find "${latest_dir}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  cp -R playwright-report/. "${latest_dir}/"
fi

if [ -d test-results ]; then
  rm -rf "${run_dir}/test-results"
  mkdir -p "${run_dir}/test-results"
  cp -R test-results/. "${run_dir}/test-results/" 2>/dev/null || true
fi

cat > reports/latest/metadata.txt <<EOF
last_run=${timestamp}
exit_code=${test_exit_code}
EOF

chmod -R a+rX reports test-results playwright-report 2>/dev/null || true

prune_history "${REPORT_HISTORY_LIMIT}"

log "Artifacts written to ${run_dir}"
log "Latest report published to ${latest_dir}"
log "Exit code: ${test_exit_code}"

exit "${test_exit_code}"
