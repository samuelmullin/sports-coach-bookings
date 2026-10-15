import { expect, test } from './fixtures';

interface Order {
  id: string;
  number: string;
  status: string;
}

test.describe('purchase a session pack', () => {
  test('adds a package to the cart, checks out, and receives the sessions once paid', async ({
    customer,
  }) => {
    const { page, request } = customer;
    // Checkout hands off to the (fake) hosted payment page; stand in for it.
    await page.route('https://provider.fake/**', (route) =>
      route.fulfill({ status: 200, contentType: 'text/html', body: '<h1>Hosted checkout</h1>' }),
    );

    await test.step('add the package to the cart', async () => {
      await page.goto('/packages');
      await page
        .getByRole('listitem')
        .filter({ hasText: 'Group U8-U10 3-Session Pack' })
        .getByRole('link', { name: 'View package' })
        .click();
      await expect(page.getByRole('heading', { name: 'Group U8-U10 3-Session Pack' })).toBeVisible();
      await page.getByRole('button', { name: 'Add to cart' }).click();
      await expect(page.getByRole('link', { name: /^Cart \(1\)/ })).toBeVisible();
    });

    await test.step('review the cart with tax', async () => {
      await page.getByRole('link', { name: /^Cart/ }).click();
      await expect(page.getByRole('heading', { name: 'Cart' })).toBeVisible();
      await expect(page.getByText('Group U8-U10 3-Session Pack (3 credits)').first()).toBeVisible();
      await expect(page.getByRole('definition').filter({ hasText: '$99.00' })).toBeVisible();
      await expect(page.getByRole('definition').filter({ hasText: '$111.87' })).toBeVisible();
    });

    let order!: Order;
    await test.step('check out and reach the hosted payment page', async () => {
      await page.getByRole('button', { name: 'Go to checkout' }).click();
      await page.waitForURL(/provider\.fake\/checkout\//);

      const orders = await (await request.get('/api/portal/orders')).json();
      const pending = (orders.data as Order[]).find((o) => o.status === 'pending_payment');
      expect(pending, 'a pending order exists').toBeTruthy();
      order = pending as Order;
      expect(page.url()).toContain(order.number);
    });

    await test.step('no sessions are granted before payment completes', async () => {
      const credits = await (await request.get('/api/portal/credits')).json();
      expect(JSON.stringify(credits.data)).not.toMatch(/"amount":[1-9]/);
    });

    await test.step('the provider reports the payment as completed', async () => {
      const webhook = await request.post('/webhooks/stripe', {
        data: {
          id: `evt_e2e_${order.id}`,
          type: 'checkout.session.completed',
          data: {
            tenant_id: customer.tenantId,
            checkout_ref: `cs_fake_${order.id}`,
            payment_ref: `pi_e2e_${order.id}`,
          },
        },
      });
      expect(webhook.status()).toBe(200);

      await expect
        .poll(
          async () => {
            const res = await request.get(`/api/portal/orders/${order.id}`);
            return ((await res.json()) as Order).status;
          },
          { message: 'order becomes paid', timeout: 20_000 },
        )
        .toBe('paid');
    });

    await test.step('the return page shows the paid order and the sessions are available', async () => {
      await page.goto(`/checkout/return?order_id=${order.id}`);
      await expect(page.getByText(/paid/i).first()).toBeVisible();

      await page.goto('/credits');
      const balance = page.getByRole('tabpanel', { name: 'Balance' }).getByRole('listitem');
      await expect(balance).toHaveCount(1);
      await expect(balance.first()).toContainText('Group U8-U10');
      await expect(balance.first()).toContainText('3');
    });
  });
});
