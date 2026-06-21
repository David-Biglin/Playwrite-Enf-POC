# Playwright Regression POC

This is a team-ready, Docker-based Playwright regression testing starter for an internal IT / Digital team.

It is designed to answer a very practical need:

- give the team a repeatable way to run browser tests without installing Playwright and browser dependencies directly on the host
- make results visible through a simple HTML report
- keep the platform easy to clone, configure, and re-run on another Linux server

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

## What this platform can do

- Run Playwright smoke tests and regression suites in Docker
- Point the same test suite at different environments by changing `.env`
- Publish the latest HTML report over HTTP for team review
- Keep historical run folders for troubleshooting and audit
- Capture raw Playwright artifacts such as screenshots and traces
- Allow test authors to add new `*.spec.ts` files without changing the platform plumbing

## Intended use

This repository is a starter platform, not a finished test pack.

Use it when you want:

- a shared internal Playwright runner
- lightweight environment-specific browser testing
- manual or scheduled regression execution
- a clean baseline for building a broader UI automation suite

It is not trying to be:

- a full CI/CD pipeline by itself
- a secret-management solution
- a completed page-object test framework

## Prerequisites

Before standing this up, make sure the target host has:

- Docker installed and running
- either `docker compose` or `docker-compose`
- Git
- network access to the target application under test
- a user account that can run Docker commands

Recommended host profile:

- Linux server or VM
- at least 2 CPU cores
- at least 4 GB RAM for light smoke/regression use
- a stable hostname or IP if the HTML report needs to be shared on the LAN

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

Clone the repository first:

```bash
git clone git@github.com:David-Biglin/Playwrite-Enf-POC.git
cd Playwrite-Enf-POC
```

If you prefer the target path shown in the examples below:

```bash
mkdir -p /opt/playwright-regression
cd /opt/playwright-regression
git clone git@github.com:David-Biglin/Playwrite-Enf-POC.git .
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

## Environment variables

The platform is driven by a small `.env` contract:

- `REPORT_BIND_IP`: IP address to bind the NGINX report viewer to. Use `127.0.0.1` for local-only access.
- `REPORT_PORT`: Host port for the HTML report viewer.
- `PLAYWRIGHT_BASE_URL`: Base URL used by Playwright tests when they call `page.goto('/')`.
- `PLAYWRIGHT_WORKERS`: Parallel worker count used during test execution.
- `PLAYWRIGHT_UID`: Optional host user ID for file ownership mapping.
- `PLAYWRIGHT_GID`: Optional host group ID for file ownership mapping.
- `REPORT_HISTORY_LIMIT`: Number of historical runs to keep under `reports/history/`.

For most Linux team hosts, you can leave `PLAYWRIGHT_UID` and `PLAYWRIGHT_GID` unset and let `run-tests.sh` auto-detect them.

## Quick start

For a brand-new teammate, these are the shortest steps to a working platform:

```bash
git clone git@github.com:David-Biglin/Playwrite-Enf-POC.git
cd Playwrite-Enf-POC
cp .env.example .env
docker compose up -d
./run-tests.sh
docker compose ps
```

Then open:

```text
http://127.0.0.1:8088
```

If `REPORT_BIND_IP` is set to a LAN address, use:

```text
http://<server-ip>:8088
```

## Start the environment

```bash
cd /opt/playwright-regression
docker compose up -d
```

This starts:

- the `playwright` service
- the `report-viewer` service

If `.env` is absent, the report viewer will bind to `127.0.0.1:8088` by default.

To confirm both services are healthy:

```bash
docker compose ps
docker compose logs --tail=50 report-viewer
docker compose logs --tail=50 playwright
```

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

## First-run validation

After the first execution, confirm the platform is actually working:

1. `./run-tests.sh` exits with code `0`
2. `reports/latest/metadata.txt` exists and shows the latest run timestamp
3. `reports/latest/` contains Playwright HTML report files
4. `test-results/` contains generated artifacts
5. the report viewer opens successfully in a browser

Useful checks:

```bash
cat reports/latest/metadata.txt
find reports/latest -maxdepth 2 -type f | head
find test-results -maxdepth 2 -type f | head
curl http://127.0.0.1:8088
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

## Typical team workflow

A sensible baseline workflow for the team is:

1. clone the repository
2. create a local `.env` for the target environment
3. start the containers with `docker compose up -d`
4. run `./run-tests.sh`
5. review the HTML report
6. add or update tests in `tests/`
7. rerun and confirm the report reflects the change

For multiple environments, keep the same variable names and swap values per host or per deployment.

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

Recommended authoring conventions:

- use `page.goto('/')` plus `PLAYWRIGHT_BASE_URL` instead of hard-coded hostnames in tests
- keep tests deterministic and avoid relying on manual timing
- make assertions explicit so failures are readable in the HTML report
- keep credentials and environment-specific secrets outside committed spec files
- start with smoke coverage for critical journeys before expanding into deeper regression packs

## Updating dependencies

The runner automatically refreshes dependencies when `package-lock.json` changes.

Typical update flow:

```bash
npm install <package-name> --save-dev
git add package.json package-lock.json
git commit -m "Add <package-name>"
./run-tests.sh
```

If the team upgrades Playwright itself, rerun the platform and confirm the first install completes cleanly inside the container.

## Running this on a schedule

This repository is suitable for manual runs now, and can also be scheduled later.

Typical options:

- host cron calling `./run-tests.sh`
- a CI job on a self-hosted runner
- a central test host that publishes the report URL to the team

If you schedule it, also decide:

- which environment the job targets
- how credentials are injected
- how long to keep history
- how the team is notified on failure

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
