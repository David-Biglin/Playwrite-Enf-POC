import { expect, test } from '@playwright/test';

test('@hr @smoke landing page is reachable', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveURL(/.+/);
});
