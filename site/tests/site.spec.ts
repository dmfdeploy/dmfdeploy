import { test, expect } from '@playwright/test';

const desktop = { width: 1440, height: 900 };
const mobile = { width: 390, height: 844 };

test('homepage works at desktop size and captures its layout', async ({ page }) => {
  await page.setViewportSize(desktop);
  await page.goto('/');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('A shared foundation for dynamic media.');
  await expect(page.locator('video')).toHaveAttribute('poster', '/media/film-006-poster.jpg');
  await expect(page.getByRole('link', { name: /Explore sponsorship/i })).toHaveAttribute('href', '/sponsor');
  await expect(page.getByRole('heading', { name: 'A visible operational loop.' })).toBeVisible();
  await page.screenshot({ path: 'screenshots/home-desktop.png', fullPage: true });
  await page.getByRole('button', { name: 'Play the 30-second project pitch' }).click();
  await expect.poll(() => page.locator('video').evaluate((video: HTMLVideoElement) => !video.paused)).toBe(true);
  await expect(page.locator('video')).toHaveAttribute('controls', '');
});

test('sponsorship page has the proposed levels without a payment route', async ({ page }) => {
  await page.setViewportSize(desktop);
  await page.goto('/sponsor');
  await expect(page.getByRole('heading', { level: 1 })).toHaveText('Become a founding sponsor.');
  for (const amount of ['€1,000', '€5,000', '€15,000', '€25,000+']) {
    await expect(page.getByText(amount, { exact: true })).toBeVisible();
  }
  await expect(page.getByText('Fiscal host', { exact: true })).toBeVisible();
  await expect(page.getByText('Unconfirmed', { exact: true })).toBeVisible();
  await expect(page.locator('a[href^="mailto:inquiries@dmfdeploy.io"]').first()).toBeVisible();
  await expect(page.locator('a[href*="opencollective.com"], a[href*="stripe.com"], form')).toHaveCount(0);
  await page.screenshot({ path: 'screenshots/sponsor-desktop.png', fullPage: true });
});

test('mobile homepage navigation and film control work', async ({ page }) => {
  await page.setViewportSize(mobile);
  await page.goto('/');
  const menuButton = page.getByRole('banner').getByRole('button', { name: 'Menu' });
  await expect(menuButton).toBeVisible();
  await menuButton.click();
  await expect(page.getByRole('navigation', { name: 'Mobile primary' })).toBeVisible();
  await page.keyboard.press('Escape');
  await expect(page.getByRole('navigation', { name: 'Mobile primary' })).toBeHidden();
  await expect(page.getByRole('button', { name: 'Play the 30-second project pitch' })).toBeVisible();
  const overflows = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  expect(overflows).toBe(false);
  await page.screenshot({ path: 'screenshots/home-mobile.png', fullPage: true });
});

test('mobile sponsorship layout fits and inquiry is actionable', async ({ page }) => {
  await page.setViewportSize(mobile);
  await page.goto('/sponsor');
  await expect(page.getByRole('link', { name: /Start a sponsorship conversation/i }).first()).toHaveAttribute('href', /mailto:inquiries@dmfdeploy.io/);
  await expect(page.getByText('€25,000+', { exact: true })).toBeVisible();
  const overflows = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
  expect(overflows).toBe(false);
  await page.screenshot({ path: 'screenshots/sponsor-mobile.png', fullPage: true });
});

test('both pages fit a narrow mobile viewport', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 720 });
  for (const route of ['/', '/sponsor']) {
    await page.goto(route);
    const overflows = await page.evaluate(() => document.documentElement.scrollWidth > window.innerWidth);
    expect(overflows, `${route} overflows at 320px`).toBe(false);
  }
});

test('in-page navigation targets exist', async ({ page }) => {
  for (const route of ['/', '/sponsor']) {
    await page.goto(route);
    const missing = await page.evaluate(() => [...document.querySelectorAll<HTMLAnchorElement>('a[href^="#"]')]
      .map((anchor) => anchor.getAttribute('href'))
      .filter((href): href is string => Boolean(href && href.length > 1 && !document.querySelector(href))));
    expect(missing, `${route} has broken in-page links`).toEqual([]);
  }
});
