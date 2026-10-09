import { expect, test as base, type APIRequestContext, type Page } from '@playwright/test';
import { PASSWORD, dobForAge, linkFrom, uniqueEmail, waitForEmail } from './helpers';

export interface Customer {
  page: Page;
  request: APIRequestContext;
  email: string;
  password: string;
  tenantId: string;
  householdId: string;
}

export interface Player {
  id: string;
  firstName: string;
  lastName: string;
}

async function json<T>(response: { ok(): boolean; status(): number; json(): Promise<unknown>; url(): string }): Promise<T> {
  if (!response.ok()) {
    throw new Error(`${response.url()} → ${response.status()}: ${JSON.stringify(await response.json().catch(() => null))}`);
  }
  return (await response.json()) as T;
}

/**
 * A freshly registered, email-confirmed, signed-in customer. Set up through the
 * API (the onboarding journey covers the registration UI), so each journey starts
 * from a known state without depending on another journey's data.
 */
export const test = base.extend<{ customer: Customer }>({
  customer: async ({ browser, baseURL }, use) => {
    const context = await browser.newContext({ baseURL });
    const page = await context.newPage();
    const request = context.request;
    const email = uniqueEmail('customer');

    await json(
      await request.post('/api/portal/registrations', {
        data: {
          first_name: 'Casey',
          last_name: 'Fixture',
          email,
          phone: '+19025550188',
          password: PASSWORD,
          accept_terms: true,
          accept_privacy: true,
        },
      }),
    );

    const message = await waitForEmail(request, email, /confirm/i);
    const link = new URL(linkFrom(message, /https?:\/\/[^\s"'<>]*confirm-email\?token=[^\s"'<>]+/));
    await json(
      await request.post('/api/portal/confirmation', {
        data: { token: link.searchParams.get('token') },
      }),
    );

    const account = await json<{ customer_user: { tenant_id: string } }>(
      await request.get('/api/portal/account'),
    );
    const household = await json<{ id: string }>(
      await request.get('/api/portal/household'),
    );

    await use({
      page,
      request,
      email,
      password: PASSWORD,
      tenantId: account.customer_user.tenant_id,
      householdId: household.id,
    });

    // Free any seats this journey took so repeated local runs don't fill sessions.
    const upcoming = await request.get('/api/portal/bookings?scope=upcoming');
    if (upcoming.ok()) {
      const rows = ((await upcoming.json()) as { data: Array<{ booking: { id: string } }> }).data;
      for (const row of rows) {
        await request.post(`/api/portal/bookings/${row.booking.id}/cancel`, { data: {} });
      }
    }
    await context.close();
  },
});

export { expect };

/** Creates a player with an emergency contact and every required waiver signed. */
export async function addReadyPlayer(
  customer: Customer,
  overrides: { firstName?: string; lastName?: string; age?: number; contactName?: string } = {},
): Promise<Player> {
  const { request } = customer;
  const firstName = overrides.firstName ?? 'Jordan';
  const lastName = overrides.lastName ?? 'Fixture';

  const created = await json<{ id: string }>(
    await request.post('/api/portal/players', {
      data: {
        first_name: firstName,
        last_name: lastName,
        date_of_birth: dobForAge(overrides.age ?? 9),
      },
    }),
  );

  await json(
    await request.post(`/api/portal/players/${created.id}/emergency_contacts`, {
      data: {
        name: overrides.contactName ?? 'Pat Fixture',
        phone: '+19025550199',
        relationship: 'Parent',
        priority: 1,
      },
    }),
  );

  await signAllWaivers(customer, created.id);
  return { id: created.id, firstName, lastName };
}

export async function signAllWaivers(customer: Customer, playerId: string) {
  const { request } = customer;
  const waivers = await json<{ data?: unknown[]; waivers?: unknown[] }>(
    await request.get(`/api/portal/players/${playerId}/waivers`),
  );
  const rows = (waivers.data ?? waivers.waivers ?? []) as Array<Record<string, unknown>>;
  for (const row of rows) {
    const versionId = (row.version_id ?? (row.version as { id?: string } | undefined)?.id) as
      | string
      | undefined;
    if (!versionId || row.signed === true || row.status === 'signed') continue;
    const version = await json<{ content_sha256: string }>(
      await request.get(`/api/portal/waivers/versions/${versionId}`),
    );
    await json(
      await request.post(`/api/portal/players/${playerId}/waivers/${versionId}/sign`, {
        data: {
          content_sha256: version.content_sha256,
          signer_name_typed: 'Casey Fixture',
          signer_relationship: 'Parent',
          consent_checkbox: true,
        },
      }),
    );
  }
  expect(true).toBe(true);
}

/**
 * Buys a package for the customer through the real cart/checkout API and
 * completes the payment with the provider webhook (the dev server uses the Fake
 * provider). Resolves once the order is paid and the sessions are granted.
 */
export async function buyPackage(customer: Customer, packageName: string) {
  const { request } = customer;

  const catalog = await json<{ data: Array<{ id: string; name: string }> }>(
    await request.get('/api/portal/catalog/packages'),
  );
  const pkg = catalog.data.find((p) => p.name === packageName);
  if (!pkg) throw new Error(`package "${packageName}" not found`);

  await json(
    await request.post('/api/portal/cart/lines', {
      data: { type: 'package', ref_id: pkg.id, quantity: 1 },
    }),
  );
  const checkout = await json<{ order: { id: string } }>(
    await request.post('/api/portal/checkout'),
  );
  const orderId = checkout.order.id;

  const webhook = await request.post('/webhooks/stripe', {
    data: {
      id: `evt_e2e_${orderId}`,
      type: 'checkout.session.completed',
      data: {
        tenant_id: customer.tenantId,
        checkout_ref: `cs_fake_${orderId}`,
        payment_ref: `pi_e2e_${orderId}`,
      },
    },
  });
  expect(webhook.status()).toBe(200);

  await expect
    .poll(async () => ((await (await request.get(`/api/portal/orders/${orderId}`)).json()) as { status: string }).status, {
      message: 'order becomes paid',
      timeout: 20_000,
    })
    .toBe('paid');
  // Credits are granted by a follow-up event job.
  await expect
    .poll(async () => JSON.stringify((await (await request.get('/api/portal/credits')).json()).data), {
      message: 'sessions granted',
      timeout: 20_000,
    })
    .toMatch(/"amount":[1-9]/);
}


export interface OpenSession {
  id: string;
  startsAt: string;
}

/** The soonest bookable session of an offering that still has seats. */
export async function openSession(customer: Customer, offeringName: string): Promise<OpenSession> {
  const sessions = await json<{
    data: Array<{
      session: { id: string; starts_at: string };
      offering: { name: string };
      seats_left: number;
      bookable: boolean;
    }>;
  }>(await customer.request.get('/api/portal/sessions'));

  const match = sessions.data.find(
    (row) => row.offering?.name === offeringName && row.bookable && row.seats_left > 0,
  );
  if (!match) throw new Error(`no open "${offeringName}" session`);
  return { id: match.session.id, startsAt: match.session.starts_at };
}

/** Books `playerId` into `sessionId` with purchased sessions (credits). */
export async function bookSession(customer: Customer, playerId: string, sessionId: string) {
  await json(
    await customer.request.post('/api/portal/bookings', {
      data: { player_id: playerId, session_id: sessionId, method: 'credits' },
    }),
  );
}

/** A signed-in owner API context (staff session cookie on the tenant host). */
export async function ownerApi(playwright: { request: { newContext(o: { baseURL?: string }): Promise<APIRequestContext> } }, baseURL: string | undefined, creds: { email: string; password: string }) {
  const api = await playwright.request.newContext({ baseURL });
  await json(await api.post('/api/platform/session', { data: creds }));
  return api;
}

/**
 * Creates a session that started a few minutes ago, assigned to `coachEmail`.
 * Attendance and feedback only open once a session has started, and every seeded
 * session is in the future, so coach journeys need one of these.
 */
export async function createStartedSession(
  owner: APIRequestContext,
  offeringName: string,
  coachEmail: string,
): Promise<{ id: string }> {
  const offerings = await json<{ data: Array<{ id: string; name: string }> }>(
    await owner.get('/api/staff/catalog/offerings'),
  );
  const offering = offerings.data.find((o) => o.name === offeringName);
  if (!offering) throw new Error(`offering "${offeringName}" not found`);

  const sessions = await json<{ data: Array<{ session: { venue_id: string } }> }>(
    await owner.get('/api/staff/schedule/sessions'),
  );
  const venueId = sessions.data[0]?.session.venue_id;

  const team = await json<{ data: Array<{ id: string; staff_user: { email: string } }> }>(
    await owner.get('/api/staff/team'),
  );
  const coach = team.data.find((m) => m.staff_user.email === coachEmail);
  if (!coach) throw new Error(`coach ${coachEmail} not found`);

  const startsAt = new Date(Date.now() - 10 * 60_000);
  const endsAt = new Date(startsAt.getTime() + 75 * 60_000);
  const created = await json<{ id?: string; session?: { id: string } }>(
    await owner.post('/api/staff/schedule/sessions', {
      data: {
        offering_id: offering.id,
        venue_id: venueId,
        starts_at: startsAt.toISOString(),
        ends_at: endsAt.toISOString(),
        capacity: 12,
        coach_ids: [coach.id],
        visibility: 'hidden',
      },
    }),
  );
  return { id: (created.session?.id ?? created.id) as string };
}

/** Books a player on a customer's behalf, overriding the booking window. */
export async function bookOnBehalf(owner: APIRequestContext, playerId: string, sessionId: string) {
  await json(
    await owner.post('/api/staff/bookings', {
      data: {
        player_id: playerId,
        session_id: sessionId,
        method: 'comp',
        override: true,
        reason: 'e2e: session already started',
      },
    }),
  );
}
