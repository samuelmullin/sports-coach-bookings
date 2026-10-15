import { expect, test } from '@playwright/test';
import { loginAdmin, SEEDED, uniqueEmail, waitForEmail } from './helpers';

test('an operator drafts and publishes a hosted site, then receives an inquiry', async ({
  page,
  request,
}) => {
  const headline = `Train with purpose ${Date.now()}`;
  const visitorEmail = uniqueEmail('website');

  await test.step('the owner edits a draft without changing the public site', async () => {
    await loginAdmin(page, SEEDED.owner.email, SEEDED.owner.password);
    await page.goto('/admin/website');
    await expect(page.getByRole('heading', { name: 'Website' })).toBeVisible();

    await page.getByLabel('title').first().fill(headline);
    await page.getByRole('button', { name: 'Save draft' }).click();
    await expect(page.getByText('Website draft saved', { exact: true })).toBeVisible();

    const publicDraft = await request.get('/api/portal/website');
    expect(publicDraft.status()).toBe(404);
  });

  await test.step('publishing makes the complete draft public', async () => {
    await page.getByRole('button', { name: 'Publish', exact: true }).click();
    await expect(page.getByText('Website published', { exact: true })).toBeVisible();

    await page.goto('/');
    await expect(page.getByRole('heading', { name: headline })).toBeVisible();

    const robots = await request.get('/robots.txt');
    expect(await robots.text()).toContain('/sitemap.xml');
    expect((await request.get('/sitemap.xml')).status()).toBe(200);
  });

  await test.step('a visitor submits an inquiry and the operator is notified', async () => {
    await page.goto('/contact');
    await page.getByLabel('Name').fill('Website Visitor');
    await page.getByLabel('Email').fill(visitorEmail);
    await page.getByLabel('Subject').fill('Small-group training');
    await page
      .getByLabel('Message')
      .fill('I would like to learn more about small-group basketball training.');
    await page.getByRole('button', { name: 'Send message' }).click();
    await expect(page.getByRole('heading', { name: /received your message/i })).toBeVisible();

    const message = await waitForEmail(request, 'demo@sportscoachbookings.com', /website inquiry/i);
    expect(message.text_body).toContain(visitorEmail);
  });

  await test.step('the inquiry appears in the admin inbox', async () => {
    await page.goto('/admin/website?tab=inbox');
    await expect(page.getByText(visitorEmail)).toBeVisible();
  });
});
