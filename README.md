# Playwright Regression POC

This is a team-ready, Docker-based Playwright regression testing starter for an internal IT / Digital team.

It keeps the moving parts small:

- A long-running Playwright runner container based on the official Microsoft Playwright image
- An NGINX report viewer on port `8088`, with the bind address controlled through `.env`
- A host-side `run-tests.sh` script to trigger tests and publish reports
- Persistent report folders so historical runs survive container restarts
- Host user and group mapping so generated files stay editable by the team account
- Automatic dependency refresh when `package-lock.json` changes
- Portable hardening on the report viewer container

The compose file has safe defaults and will start even if `.env` is missing:

- `REPORT_BIND_IP` defaults to `127.0.0.1`
- `REPORT_PORT` defaults to `8088`
- `PLAYWRIGHT_BASE_URL` defaults to `https://example.com`
- `PLAYWRIGHT_WORKERS` defaults to `2`
- `PLAYWRIGHT_UID` and `PLAYWRIGHT_GID` are auto-detected by `run-tests.sh` if not set
- `REPORT_HISTORY_LIMIT` defaults to `10`

For a LAN-visible deployment, copy `.env.example` to `.env` and set the host IP you want to bind.

## Folder structure

```text
/opt/playwright-regression/
├── docker-compose.yml
├── .env.example
├── .gitignore
├── nginx/
│   └── default.conf
├── package.json
├── playwright.config.ts
├── README.md
├── reports/
│   ├── history/
│   └── latest/
├── run-tests.sh
├── test-results/
└── tests/
    └── example.spec.ts
```

## What each file does

- `docker-compose.yml`: Defines the Playwright runner container and the NGINX report viewer using the official Microsoft Playwright image.
- `.env.example`: Template values for bind IP, target URL, ownership mapping, and report retention.
- `.gitignore`: Keeps generated reports, test artifacts, dependencies, and local `.env` out of Git.
- `package.json`: Holds the Playwright dependency and helper scripts.
- `package-lock.json`: Pins the dependency versions for repeatable first-run installs.
- `playwright.config.ts`: Configures the browser project, artifacts, timeouts, and HTML reporting.
- `tests/example.spec.ts`: Sample test that proves the platform works against a public site.
- `run-tests.sh`: Manual trigger script that runs the suite, archives the report, and publishes the latest HTML report.
- `nginx/default.conf`: Serves the latest report cleanly and disables directory browsing.
- `reports/history/`: Timestamped archive of previous HTML reports and test results.
- `reports/latest/`: The report currently served by NGINX.
- `test-results/`: Raw Playwright artifacts such as screenshots and traces for the latest run.
- `.state/`: Local runtime metadata such as the last installed `package-lock.json` hash.

## Setup on a fresh server

```bash
mkdir -p /opt/playwright-regression
cd /opt/playwright-regression
cp .env.example .env
```

Edit `.env` only if you want network access beyond localhost.

Default localhost-only example:

```bash
REPORT_BIND_IP=127.0.0.1
REPORT_PORT=8088
PLAYWRIGHT_BASE_URL=https://example.com
PLAYWRIGHT_WORKERS=2
REPORT_HISTORY_LIMIT=10
```

Example for a LAN-visible host:

```bash
REPORT_BIND_IP=192.168.0.169
REPORT_PORT=8088
PLAYWRIGHT_BASE_URL=https://internal-test-target.example
PLAYWRIGHT_WORKERS=4
REPORT_HISTORY_LIMIT=20
```

If you need explicit Linux ownership mapping, also set:

```bash
PLAYWRIGHT_UID=1000
PLAYWRIGHT_GID=1000
```

Suggested team convention:

- Keep `.env.example` in Git as the contract.
- Create a real `.env` per host and per environment.
- Put credentials in a separate untracked secret source when tests move beyond anonymous smoke checks.

## Start the environment

```bash
cd /opt/playwright-regression
docker compose up -d
```

This starts:

- the `playwright` service
- the `report-viewer` service

If `.env` is absent, the report viewer will bind to `127.0.0.1:8088` by default.

## Run the tests manually

```bash
cd /opt/playwright-regression
./run-tests.sh
```

The script will:

1. Start the containers if they are not already running
2. Run the Playwright container as the current host user unless overridden in `.env`
3. Fail early if Docker is installed but the daemon is unavailable
4. Reinstall Node dependencies when `package-lock.json` changes
5. Execute the Playwright tests inside the official Microsoft container
6. Keep raw artifacts in `test-results/`
7. Copy the HTML report to `reports/history/<timestamp>/html-report/`
8. Publish the newest report into `reports/latest/` for NGINX to serve
9. Prune older report history beyond `REPORT_HISTORY_LIMIT`

Useful commands:

```bash
./run-tests.sh
npm run test:smoke
docker compose ps
docker compose logs -f report-viewer
```

## View the reports

If using localhost-only bind:

```bash
curl http://127.0.0.1:8088
```

If using a LAN bind, browse to:

```text
http://<server-ip>:8088
```

If you prefer SSH tunnelling instead:

```bash
ssh -L 8088:127.0.0.1:8088 <server>
```

Then browse to `http://127.0.0.1:8088`.

## Add new Playwright tests

Add new `*.spec.ts` files inside `tests/`.

Example pattern:

```ts
import { expect, test } from '@playwright/test';

test('homepage check', async ({ page }) => {
  await page.goto('https://your-site.example');
  await expect(page).toHaveTitle(/Expected title/);
});
```

After adding tests, rerun:

```bash
./run-tests.sh
```

For a minimal post-change check, you can also run:

```bash
npm run test:smoke
```

## Troubleshooting

- `docker compose up -d` fails:
  Check that Docker is running and the current user is in the `docker` group.
- `Docker is installed but the daemon is not reachable`:
  Start Docker Desktop or the Docker service first, then rerun `./run-tests.sh`.
- The report viewer is not reachable on the network:
  Check `.env`, then run `docker compose up -d --force-recreate report-viewer`.
- The first dependency install is slow:
  That is expected because the container is populating `node_modules/` from `package-lock.json`.
- Dependencies do not reflect the latest lockfile:
  Rerun `./run-tests.sh`; it now refreshes dependencies automatically when `package-lock.json` changes.
- Generated files are owned by the wrong user:
  Set `PLAYWRIGHT_UID` and `PLAYWRIGHT_GID` in `.env`, then rerun `docker compose up -d --force-recreate playwright`.
- The report page is blank:
  Run `./run-tests.sh` first so `reports/latest/` is populated with a real Playwright report.
- Port `8088` is already in use:
  Change `REPORT_PORT` in `.env`, then recreate `report-viewer`.
- Browsers crash or become unstable:
  Increase `shm_size` in `docker-compose.yml`.
- You need credentials for future internal-site tests:
  Do not hard-code them here. Use environment variables or a mounted secret file later.

## Security notes

- This setup is for internal testing only.
- The report viewer bind is explicit and controlled through `.env`.
- No credentials are stored in plain text in this proof of concept.
- If you later test authenticated sites, add a `.env` file or mounted secret source and document the required variables without committing values.
- The report viewer uses a read-only filesystem and `no-new-privileges` without relying on host-specific container privileges.

## Team Handoff Notes

- Treat this repository as a starter pattern rather than a finished test suite.
- Keep shared tests deterministic and avoid hard-coding environment-specific URLs in spec files.
- Prefer one `.env` per environment such as dev, UAT, or pre-prod, with the same variable names.
- If the team later wants unattended scheduled runs, add a host cron or CI job that calls `./run-tests.sh` and publishes the HTML report location.
