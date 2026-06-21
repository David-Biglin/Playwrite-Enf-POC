import { defineConfig, devices } from '@playwright/test';

const baseURL = process.env.PLAYWRIGHT_BASE_URL || 'https://example.com';
const environmentName = process.env.PLAYWRIGHT_ENVIRONMENT || 'local';
const platformName = process.env.PLAYWRIGHT_PLATFORM || 'shared';
const workerOverride = Number.parseInt(process.env.PLAYWRIGHT_WORKERS || '', 10);
const workers = Number.isFinite(workerOverride) && workerOverride > 0
  ? workerOverride
  : (process.env.CI ? 2 : undefined);

export default defineConfig({
  testDir: './tests',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 1 : 0,
  workers,
  timeout: 30_000,
  expect: {
    timeout: 5_000,
  },
  reporter: [
    ['list'],
    ['html', { outputFolder: 'playwright-report', open: 'never' }],
  ],
  outputDir: 'test-results',
  metadata: {
    environment: environmentName,
    platform: platformName,
    baseURL,
  },
  use: {
    baseURL,
    trace: 'on',
    screenshot: 'on',
    video: 'off',
    viewport: { width: 1440, height: 900 },
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
  ],
});
