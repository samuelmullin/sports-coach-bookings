import { defineConfig } from '@playwright/test';

const PORT = process.env.E2E_PORT ?? '4010';
const DB_NAME = process.env.DEV_DB_NAME ?? 'sports_coach_bookings_e2e';

export const BASE_URL = `http://demo.localhost:${PORT}`;

export default defineConfig({
  testDir: './tests',
  // Journeys share one seeded database and build on each other's state.
  fullyParallel: false,
  workers: 1,
  retries: process.env.CI ? 1 : 0,
  timeout: 45_000,
  expect: { timeout: 10_000 },
  reporter: process.env.CI ? [['github'], ['html', { open: 'never' }]] : [['list']],
  use: {
    baseURL: BASE_URL,
    // Locally use the installed Chrome; CI installs bundled Chromium instead.
    channel: process.env.E2E_BROWSER_CHANNEL ?? (process.env.CI ? undefined : 'chrome'),
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  webServer: {
    // Boots Phoenix against the dedicated e2e database (see scripts/reset-db.sh).
    // The SPAs must already be built: `pnpm --dir ../frontend build`.
    command: 'mix phx.server',
    cwd: '../backend',
    env: { MIX_ENV: 'dev', DEV_DB_NAME: DB_NAME, PORT, RATE_LIMITING: 'off' },
    url: `${BASE_URL}/api/portal/ping`,
    reuseExistingServer: !process.env.CI,
    timeout: 180_000,
    stdout: 'ignore',
    stderr: 'pipe',
  },
});
