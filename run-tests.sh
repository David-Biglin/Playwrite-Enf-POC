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
export PLAYWRIGHT_TARGET="${PLAYWRIGHT_TARGET:-}"
export PLAYWRIGHT_PLATFORM="${PLAYWRIGHT_PLATFORM:-all}"
export PLAYWRIGHT_ENVIRONMENT="${PLAYWRIGHT_ENVIRONMENT:-local}"
export PLAYWRIGHT_SUITE="${PLAYWRIGHT_SUITE:-all}"
export PLAYWRIGHT_GREP="${PLAYWRIGHT_GREP:-}"
export PLAYWRIGHT_GREP_INVERT="${PLAYWRIGHT_GREP_INVERT:-}"

timestamp="$(date '+%Y%m%d-%H%M%S')"
run_dir="reports/history/${timestamp}"
latest_dir="reports/latest"
state_dir=".state"
lock_hash_file="${state_dir}/package-lock.sha256"
default_env_file=".env"
platform_filter=""
suite_filter=""
environment_file=""
latest_report_dir="${latest_dir}/report"
test_path=""

mkdir -p "$run_dir" "$latest_dir" "$latest_report_dir" test-results playwright-report "$state_dir"
chmod 755 reports reports/history "$latest_dir" "$latest_report_dir" test-results playwright-report "$state_dir" 2>/dev/null || true

log() {
  printf '[playwright-regression] %s\n' "$*"
}

fail() {
  log "$*"
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  ./run-tests.sh
  ./run-tests.sh --target d365-uat
  ./run-tests.sh --platform d365 --suite smoke --environment uat
  ./run-tests.sh --env-file config/environments/d365-uat.env
  ./run-tests.sh --grep @smoke

Options:
  --target <name>       Load config/environments/<name>.env and set the target label
  --platform <name>     Filter tests by platform tag such as d365, hr, or assets
  --suite <name>        Filter tests by suite tag such as smoke or regression
  --environment <name>  Logical environment label shown in metadata and report landing page
  --env-file <path>     Load a target environment file after .env
  --grep <pattern>      Additional Playwright grep pattern
  --grep-invert <expr>  Exclude tests matching a Playwright grep pattern
  --list-targets        Show available checked-in target templates and local target files
  --help                Show this help text
EOF
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

shell_escape() {
  printf '%s' "$1" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g' \
    -e 's/"/\&quot;/g' \
    -e "s/'/\&#39;/g"
}

build_history_links() {
  local history_root="reports/history"
  local entry
  local count=0
  local status_class status_text metadata_file platform environment suite run_target

  while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    count=$((count + 1))
    [ "$count" -le 10 ] || break
    metadata_file="${history_root}/${entry}/metadata.txt"
    if [ ! -f "${metadata_file}" ]; then
      continue
    fi

    status_text="Unknown"
    status_class="status-unknown"
    platform="unknown"
    environment="unknown"
    suite="unknown"
    run_target=""

    while IFS='=' read -r key value; do
      case "$key" in
        exit_code)
          if [ "$value" = "0" ]; then
            status_text="Passing"
            status_class="status-pass"
          else
            status_text="Failing"
            status_class="status-fail"
          fi
          ;;
        platform)
          platform="$(shell_escape "$value")"
          ;;
        environment)
          environment="$(shell_escape "$value")"
          ;;
        suite)
          suite="$(shell_escape "$value")"
          ;;
        target)
          run_target="$(shell_escape "$value")"
          ;;
      esac
    done < "${metadata_file}"

    printf '<li><a href="/history/%s/html-report/index.html">%s</a> <span class="%s">%s</span><br><span class="history-meta">Platform: %s | Environment: %s | Suite: %s' \
      "$entry" "$entry" "$status_class" "$status_text" "$platform" "$environment" "$suite"
    if [ -n "$run_target" ]; then
      printf ' | Target: %s' "$run_target"
    fi
    printf '</span></li>\n'
  done <<EOF
$(find "$history_root" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort -r)
EOF

  if [ "$count" -eq 0 ]; then
    printf '<li>No archived runs yet.</li>\n'
  fi
}

write_latest_index() {
  local exit_code="$1"
  local report_url="./report/index.html"
  local escaped_platform escaped_environment escaped_suite escaped_base_url escaped_timestamp escaped_target
  local status_text status_class history_links

  escaped_platform="$(shell_escape "${PLAYWRIGHT_PLATFORM}")"
  escaped_environment="$(shell_escape "${PLAYWRIGHT_ENVIRONMENT}")"
  escaped_suite="$(shell_escape "${PLAYWRIGHT_SUITE}")"
  escaped_base_url="$(shell_escape "${PLAYWRIGHT_BASE_URL}")"
  escaped_timestamp="$(shell_escape "${timestamp}")"
  escaped_target="$(shell_escape "${PLAYWRIGHT_TARGET:-manual}")"

  if [ "$exit_code" -eq 0 ]; then
    status_text="Passing"
    status_class="status-pass"
  else
    status_text="Failing"
    status_class="status-fail"
  fi

  history_links="$(build_history_links)"

  cat > "${latest_dir}/index.html" <<EOF
<!doctype html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Playwright Test Status</title>
    <style>
      :root {
        color-scheme: light;
        --bg: #f5f7fb;
        --panel: #ffffff;
        --text: #172033;
        --muted: #5f6f8f;
        --accent: #1447e6;
        --border: #d7dff0;
        --good: #0f8a4b;
        --bad: #c03221;
      }
      * { box-sizing: border-box; }
      body {
        margin: 0;
        font-family: "Segoe UI", Helvetica, Arial, sans-serif;
        background: linear-gradient(180deg, #eef3ff 0%, var(--bg) 100%);
        color: var(--text);
      }
      main {
        max-width: 980px;
        margin: 0 auto;
        padding: 40px 20px 64px;
      }
      .hero, .panel {
        background: var(--panel);
        border: 1px solid var(--border);
        border-radius: 18px;
        box-shadow: 0 18px 40px rgba(20, 38, 74, 0.08);
      }
      .hero {
        padding: 28px;
        margin-bottom: 20px;
      }
      .panel {
        padding: 24px;
        margin-bottom: 20px;
      }
      h1, h2 { margin: 0 0 12px; }
      p { margin: 0; color: var(--muted); }
      .status {
        display: inline-block;
        padding: 8px 12px;
        border-radius: 999px;
        font-weight: 600;
        margin-bottom: 18px;
      }
      .status-pass { background: #e9fbf1; color: var(--good); }
      .status-fail { background: #fff1ef; color: var(--bad); }
      .status-unknown { background: #eef2ff; color: #41527a; }
      .grid {
        display: grid;
        grid-template-columns: repeat(auto-fit, minmax(220px, 1fr));
        gap: 14px;
        margin-top: 20px;
      }
      .metric {
        border: 1px solid var(--border);
        border-radius: 14px;
        padding: 14px 16px;
        background: #fbfcff;
      }
      .metric strong {
        display: block;
        margin-bottom: 6px;
      }
      a {
        color: var(--accent);
        text-decoration: none;
      }
      a:hover { text-decoration: underline; }
      ul {
        margin: 12px 0 0;
        padding-left: 20px;
      }
      .history-meta {
        color: var(--muted);
        font-size: 0.95rem;
      }
      code {
        font-family: "SFMono-Regular", Consolas, monospace;
        background: #f2f5fb;
        padding: 2px 6px;
        border-radius: 6px;
      }
    </style>
  </head>
  <body>
    <main>
      <section class="hero">
        <div class="status ${status_class}">${status_text}</div>
        <h1>Playwright Platform Status</h1>
        <p>Latest published result for the shared internal browser testing platform.</p>
        <div class="grid">
          <div class="metric">
            <strong>Platform</strong>
            <span>${escaped_platform}</span>
          </div>
          <div class="metric">
            <strong>Environment</strong>
            <span>${escaped_environment}</span>
          </div>
          <div class="metric">
            <strong>Suite</strong>
            <span>${escaped_suite}</span>
          </div>
          <div class="metric">
            <strong>Target</strong>
            <span>${escaped_target}</span>
          </div>
          <div class="metric">
            <strong>Executed</strong>
            <span>${escaped_timestamp}</span>
          </div>
        </div>
      </section>
      <section class="panel">
        <h2>Current Run</h2>
        <p>Target URL: <code>${escaped_base_url}</code></p>
        <ul>
          <li><a href="${report_url}">Open the full Playwright HTML report</a></li>
          <li><a href="./metadata.txt">Open raw run metadata</a></li>
        </ul>
      </section>
      <section class="panel">
        <h2>Recent History</h2>
        <p>Most recent archived runs kept under <code>reports/history/</code>.</p>
        <ul>
${history_links}
        </ul>
      </section>
    </main>
  </body>
</html>
EOF
}

list_targets() {
  local target_file

  log "Checked-in target templates:"
  if compgen -G "config/environments/*.env.example" >/dev/null 2>&1; then
    for target_file in config/environments/*.env.example; do
      printf '  - %s\n' "$(basename "$target_file" .env.example)"
    done
  else
    printf '  (none)\n'
  fi

  log "Local target files:"
  if compgen -G "config/environments/*.env" >/dev/null 2>&1; then
    for target_file in config/environments/*.env; do
      printf '  - %s\n' "$(basename "$target_file" .env)"
    done
  else
    printf '  (none)\n'
  fi
}

combine_grep_patterns() {
  local combined=""
  local pattern

  for pattern in "$@"; do
    [ -n "$pattern" ] || continue
    combined="${combined}(?=.*(${pattern}))"
  done

  printf '%s' "$combined"
}

resolve_target_file() {
  local target_name="$1"
  local local_target="config/environments/${target_name}.env"
  local template_target="config/environments/${target_name}.env.example"

  if [ -f "$local_target" ]; then
    printf '%s' "$local_target"
    return 0
  fi

  if [ -f "$template_target" ]; then
    fail "Target '${target_name}' only has a template. Copy ${template_target} to ${local_target} and fill in real values."
  fi

  fail "Target '${target_name}' was not found under config/environments/."
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --target)
      [ "$#" -ge 2 ] || fail "Missing value for --target"
      PLAYWRIGHT_TARGET="$2"
      shift 2
      ;;
    --platform)
      [ "$#" -ge 2 ] || fail "Missing value for --platform"
      PLAYWRIGHT_PLATFORM="$2"
      shift 2
      ;;
    --suite)
      [ "$#" -ge 2 ] || fail "Missing value for --suite"
      PLAYWRIGHT_SUITE="$2"
      shift 2
      ;;
    --environment)
      [ "$#" -ge 2 ] || fail "Missing value for --environment"
      PLAYWRIGHT_ENVIRONMENT="$2"
      shift 2
      ;;
    --env-file)
      [ "$#" -ge 2 ] || fail "Missing value for --env-file"
      environment_file="$2"
      shift 2
      ;;
    --grep)
      [ "$#" -ge 2 ] || fail "Missing value for --grep"
      PLAYWRIGHT_GREP="$2"
      shift 2
      ;;
    --grep-invert)
      [ "$#" -ge 2 ] || fail "Missing value for --grep-invert"
      PLAYWRIGHT_GREP_INVERT="$2"
      shift 2
      ;;
    --list-targets)
      list_targets
      exit 0
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      fail "Unknown argument: $1"
      ;;
  esac
done

[ -f "${default_env_file}" ] && . "${default_env_file}"

if [ -n "${environment_file}" ]; then
  [ -f "${environment_file}" ] || fail "Environment file not found: ${environment_file}"
  . "${environment_file}"
fi

[ "${PLAYWRIGHT_PLATFORM}" = "all" ] || platform_filter="@${PLAYWRIGHT_PLATFORM}"
[ "${PLAYWRIGHT_SUITE}" = "all" ] || suite_filter="@${PLAYWRIGHT_SUITE}"

if [ -n "${platform_filter}" ] && [ -n "${suite_filter}" ]; then
  PLAYWRIGHT_GREP="${platform_filter}.*${suite_filter}|${suite_filter}.*${platform_filter}"
elif [ -n "${platform_filter}" ]; then
  PLAYWRIGHT_GREP="${platform_filter}"
elif [ -n "${suite_filter}" ] && [ -z "${PLAYWRIGHT_GREP}" ]; then
  PLAYWRIGHT_GREP="${suite_filter}"
fi

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
playwright_cmd=(npx playwright test)

if [ -n "${PLAYWRIGHT_GREP}" ]; then
  playwright_cmd+=(--grep "${PLAYWRIGHT_GREP}")
fi

if [ -n "${PLAYWRIGHT_GREP_INVERT}" ]; then
  playwright_cmd+=(--grep-invert "${PLAYWRIGHT_GREP_INVERT}")
fi

log "Platform: ${PLAYWRIGHT_PLATFORM}"
log "Environment: ${PLAYWRIGHT_ENVIRONMENT}"
log "Suite: ${PLAYWRIGHT_SUITE}"
log "Base URL: ${PLAYWRIGHT_BASE_URL}"
set +e
"${compose_cmd[@]}" exec -T \
  -e PLAYWRIGHT_BASE_URL="${PLAYWRIGHT_BASE_URL}" \
  -e PLAYWRIGHT_WORKERS="${PLAYWRIGHT_WORKERS}" \
  -e PLAYWRIGHT_PLATFORM="${PLAYWRIGHT_PLATFORM}" \
  -e PLAYWRIGHT_ENVIRONMENT="${PLAYWRIGHT_ENVIRONMENT}" \
  playwright \
  "${playwright_cmd[@]}"
test_exit_code=$?
set -e

if [ -d playwright-report ]; then
  rm -rf "${run_dir}/html-report"
  mkdir -p "${run_dir}/html-report"
  cp -R playwright-report/. "${run_dir}/html-report/"

  mkdir -p "${latest_dir}"
  find "${latest_report_dir}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  cp -R playwright-report/. "${latest_report_dir}/"
fi

if [ -d test-results ]; then
  rm -rf "${run_dir}/test-results"
  mkdir -p "${run_dir}/test-results"
  cp -R test-results/. "${run_dir}/test-results/" 2>/dev/null || true
fi

cat > reports/latest/metadata.txt <<EOF
last_run=${timestamp}
exit_code=${test_exit_code}
platform=${PLAYWRIGHT_PLATFORM}
environment=${PLAYWRIGHT_ENVIRONMENT}
suite=${PLAYWRIGHT_SUITE}
base_url=${PLAYWRIGHT_BASE_URL}
EOF

cat > "${run_dir}/metadata.txt" <<EOF
last_run=${timestamp}
exit_code=${test_exit_code}
platform=${PLAYWRIGHT_PLATFORM}
environment=${PLAYWRIGHT_ENVIRONMENT}
suite=${PLAYWRIGHT_SUITE}
base_url=${PLAYWRIGHT_BASE_URL}
EOF

write_latest_index "${test_exit_code}"

chmod -R a+rX reports test-results playwright-report 2>/dev/null || true

prune_history "${REPORT_HISTORY_LIMIT}"

log "Artifacts written to ${run_dir}"
log "Latest report published to ${latest_dir}"
log "Exit code: ${test_exit_code}"

exit "${test_exit_code}"
