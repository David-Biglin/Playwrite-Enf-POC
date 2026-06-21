import { expect, test } from '@playwright/test';

test('@d365 @smoke landing page is reachable', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveURL(/.+/);
});
