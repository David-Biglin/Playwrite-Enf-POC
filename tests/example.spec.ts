import { expect, test } from '@playwright/test';

test('example.com loads and shows the expected heading', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveTitle(/Example Domain/);

  const heading = page.getByRole('heading', { name: 'Example Domain' });
  await expect(heading).toBeVisible();

  await page.screenshot({
    path: 'test-results/example-homepage.png',
    fullPage: true,
  });
});
