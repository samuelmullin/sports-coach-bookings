import type { APIRequestContext, Browser, BrowserContext } from '@playwright/test';
import {
  addReadyPlayer,
  bookSession,
  expect,
  ownerApi,
  test,
  type Customer,
} from './fixtures';
import { PASSWORD, SEEDED, linkFrom, loginAdmin, pickOption, uniqueEmail, waitForEmail } from './helpers';

async function json<T>(response: {
  ok(): boolean;
  status(): number;
  json(): Promise<unknown>;
  url(): string;
}): Promise<T> {
  if (!response.ok()) {
    throw new Error(
      `${response.url()} → ${response.status()}: ${JSON.stringify(await response.json().catch(() => null))}`,
    );
  }
  return (await response.json()) as T;
}

async function createCustomer(
  browser: Browser,
  baseURL: string | undefined,
  prefix: string,
): Promise<{ customer: Customer; context: BrowserContext }> {
  const context = await browser.newContext({ baseURL });
  const page = await context.newPage();
  const request = context.request;
  const email = uniqueEmail(prefix);

  await json(
    await request.post('/api/portal/registrations', {
      data: {
        first_name: 'Taylor',
        last_name: 'Invitee',
        email,
        phone: '+19025550177',
        password: PASSWORD,
        accept_terms: true,
        accept_privacy: true,
      },
    }),
  );
  const confirmation = await waitForEmail(request, email, /confirm/i);
  const link = new URL(
    linkFrom(confirmation, /https?:\/\/[^\s"'<>]*confirm-email\?token=[^\s"'<>]+/),
  );
  await json(
    await request.post('/api/portal/confirmation', {
      data: { token: link.searchParams.get('token') },
    }),
  );
  const account = await json<{ customer_user: { tenant_id: string } }>(
    await request.get('/api/portal/account'),
  );
  const household = await json<{ id: string }>(await request.get('/api/portal/household'));

  return {
    customer: {
      page,
      request,
      email,
      password: PASSWORD,
      tenantId: account.customer_user.tenant_id,
      householdId: household.id,
    },
    context,
  };
}

async function createOffering(owner: APIRequestContext, suffix: string) {
  return json<{ id: string; name: string }>(
    await owner.post('/api/staff/catalog/offerings', {
      data: {
        name: `Party Skills ${suffix}`,
        format: 'semi_private',
        duration_minutes: 60,
        default_capacity: 2,
        credit_cost: 1,
        drop_in_price: 5000,
        taxable: false,
        active: true,
        public_enabled: true,
        public_max_players: 2,
        public_players_per_coach: 2,
        public_price_tiers: {
          '1': { price: 7000, credit_cost: 1 },
          '2': { price: 5000, credit_cost: 1 },
        },
        private_enabled: true,
        private_max_players: 4,
        private_players_per_coach: 4,
        private_price_tiers: {
          '1': { price: 9000, credit_cost: 2 },
          '2': { price: 6500, credit_cost: 2 },
          '3': { price: 5000, credit_cost: 1 },
          '4': { price: 4000, credit_cost: 1 },
        },
        allow_invite_reservations: true,
        invite_hold_hours: 48,
        allow_private_conversion: true,
        allow_private_requests: true,
      },
    }),
  );
}

async function schedulingReferences(owner: APIRequestContext) {
  const sessions = await json<{ data: Array<{ session: { venue_id: string } }> }>(
    await owner.get('/api/staff/schedule/sessions'),
  );
  const team = await json<{ data: Array<{ id: string; staff_user: { email: string } }> }>(
    await owner.get('/api/staff/team'),
  );
  const coach = team.data.find((member) => member.staff_user.email === SEEDED.coach.email);
  if (!coach || !sessions.data[0]?.session.venue_id) throw new Error('missing seeded schedule data');
  return { coachId: coach.id, venueId: sessions.data[0].session.venue_id };
}

async function createSession(
  owner: APIRequestContext,
  offeringId: string,
  venueId: string,
  coachId: string,
  hoursFromNow: number,
) {
  const startsAt = new Date(Date.now() + hoursFromNow * 60 * 60_000);
  const endsAt = new Date(startsAt.getTime() + 60 * 60_000);
  const result = await json<{ id?: string; session?: { id: string } }>(
    await owner.post('/api/staff/schedule/sessions', {
      data: {
        offering_id: offeringId,
        venue_id: venueId,
        starts_at: startsAt.toISOString(),
        ends_at: endsAt.toISOString(),
        capacity: 2,
        coach_ids: [coachId],
        visibility: 'public',
        access_mode: 'public',
      },
    }),
  );
  return { id: (result.session?.id ?? result.id) as string, startsAt };
}

async function grantCredits(owner: APIRequestContext, householdId: string, amount = 10) {
  await json(
    await owner.post(`/api/staff/households/${householdId}/credits/grant`, {
      data: { amount, note: 'e2e session party journey' },
    }),
  );
}

test.describe('public and private session parties', () => {
  test('invites another household, converts capacity, and completes private-request review', async ({
    customer: organizer,
    browser,
    baseURL,
    playwright,
  }) => {
    const { customer: invitee, context: inviteeContext } = await createCustomer(
      browser,
      baseURL,
      'session-invitee',
    );
    const organizerPlayer = await addReadyPlayer(organizer, {
      firstName: 'Morgan',
      lastName: 'Organizer',
    });
    const inviteePlayer = await addReadyPlayer(invitee, {
      firstName: 'Riley',
      lastName: 'Invitee',
    });
    const owner = await ownerApi(playwright, baseURL, SEEDED.owner);
    const suffix = Date.now().toString().slice(-6);
    const offering = await createOffering(owner, suffix);
    const refs = await schedulingReferences(owner);
    const inviteSession = await createSession(owner, offering.id, refs.venueId, refs.coachId, 168);
    const partnerSession = await createSession(owner, offering.id, refs.venueId, refs.coachId, 192);
    const conversionSession = await createSession(owner, offering.id, refs.venueId, refs.coachId, 216);
    const requestSession = await createSession(owner, offering.id, refs.venueId, refs.coachId, 240);
    const cutoffSession = await createSession(owner, offering.id, refs.venueId, refs.coachId, 24);
    await grantCredits(owner, organizer.householdId);
    await grantCredits(owner, invitee.householdId);

    await bookSession(organizer, organizerPlayer.id, inviteSession.id);

    await test.step('the organizer sends a split invitation in the portal', async () => {
      await organizer.page.goto('/bookings');
      await organizer.page.getByRole('button', { name: 'Invite someone' }).click();
      const dialog = organizer.page.getByRole('dialog', { name: 'Invite another player' });
      await dialog.getByLabel('Invite by email').fill(invitee.email);
      await dialog.getByRole('button', { name: 'Send invitation' }).click();
      await expect(organizer.page.getByText('Invitation sent', { exact: true })).toBeVisible();
      await expect(organizer.page.getByText(`To ${invitee.email}`)).toBeVisible();
    });

    await test.step('the invited household accepts with its own player and credit', async () => {
      const message = await waitForEmail(invitee.request, invitee.email, /invited/i);
      const invitationUrl = new URL(
        linkFrom(message, /https?:\/\/[^\s"'<>]*\/session-invites\/[^\s"'<>]+/),
      );
      await invitee.page.goto(`${invitationUrl.pathname}${invitationUrl.search}`);
      await expect(
        invitee.page.getByRole('heading', { name: 'Accept session invitation' }),
      ).toBeVisible();
      await pickOption(invitee.page, 'Player', 'Riley Invitee');
      await invitee.page.getByRole('radio', { name: 'Use session credits' }).click();
      await invitee.page.getByRole('button', { name: 'Accept invitation' }).click();
      await expect(invitee.page).toHaveURL(/\/bookings$/);
      await expect(invitee.page.getByText('Invitation for')).toBeVisible();
      await expect(invitee.page.getByText('accepted', { exact: true })).toBeVisible();
    });

    await test.step('the accepted invitee becomes a selectable previous partner', async () => {
      await bookSession(organizer, organizerPlayer.id, partnerSession.id);
      await organizer.page.goto('/bookings');
      await organizer.page.getByRole('button', { name: 'Invite someone' }).click();
      const dialog = organizer.page.getByRole('dialog', { name: 'Invite another player' });
      await dialog.getByRole('button', { name: invitee.email }).click();
      await expect(dialog.getByLabel('Invite by email')).toHaveValue(invitee.email);
      await dialog.getByRole('button', { name: 'Send invitation' }).click();
      const pending = organizer.page
        .getByRole('listitem')
        .filter({ hasText: `To ${invitee.email}` })
        .filter({ hasText: 'pending' });
      await expect(pending).toBeVisible();
      await pending.getByRole('button', { name: 'Resend' }).click();
      await expect(organizer.page.getByText('Invitation resent', { exact: true })).toBeVisible();
      await pending.getByRole('button', { name: 'Revoke' }).click();
      await expect(organizer.page.getByText('Invitation cancelled', { exact: true })).toBeVisible();
      await expect(
        organizer.page
          .getByRole('listitem')
          .filter({ hasText: `To ${invitee.email}` })
          .filter({ hasText: 'cancelled' }),
      ).toBeVisible();
    });

    await test.step('split holds close inside the cutoff but purchased guest seats remain available', async () => {
      await bookSession(organizer, organizerPlayer.id, cutoffSession.id);
      const refused = await organizer.request.post(
        `/api/portal/bookings/sessions/${cutoffSession.id}/invitations`,
        { data: { email: uniqueEmail('cutoff-split'), payment_mode: 'split' } },
      );
      expect(refused.status()).toBe(422);
      const purchased = await organizer.request.post(
        `/api/portal/bookings/sessions/${cutoffSession.id}/invitations`,
        {
          data: {
            email: uniqueEmail('cutoff-sponsored'),
            payment_mode: 'organizer',
            method: 'credits',
          },
        },
      );
      expect(purchased.status()).toBe(201);
    });

    await test.step('an empty two-player public occurrence converts to private capacity four', async () => {
      await organizer.page.goto(`/sessions/${conversionSession.id}`);
      await organizer.page.getByRole('button', { name: 'Make this session private' }).click();
      const dialog = organizer.page.getByRole('dialog', { name: 'Make this session private' });
      await dialog.getByLabel('Party size').fill('4');
      await dialog.getByRole('button', { name: 'Reserve private session' }).click();
      await expect(
        organizer.page.getByText('This time is now reserved for your private party', {
          exact: true,
        }),
      ).toBeVisible();
      await expect(organizer.page.getByText('4 of 4 seats left')).toBeVisible();
    });

    await test.step('the customer requests a private session from the offering', async () => {
      await organizer.page.goto(`/offerings/${offering.id}`);
      await organizer.page.getByRole('button', { name: 'Request private session' }).click();
      const dialog = organizer.page.getByRole('dialog', { name: 'Request a private session' });
      await dialog.getByLabel(/Number of players/).fill('4');
      await dialog.getByLabel('Notes').fill('Four-player family session');
      await dialog.getByRole('button', { name: 'Send request' }).click();
      await expect(
        organizer.page.getByText('Private session request sent', { exact: true }),
      ).toBeVisible();
      await organizer.page.goto('/private-session-requests');
      await expect(organizer.page.getByText('pending', { exact: true })).toBeVisible();
    });

    await test.step('the owner approves it and the household sees the decision', async () => {
      const adminContext = await browser.newContext({ baseURL });
      const admin = await adminContext.newPage();
      await loginAdmin(admin, SEEDED.owner.email, SEEDED.owner.password);
      await admin.goto('/admin/catalog/private-requests');
      const requestCard = admin.getByRole('listitem').filter({ hasText: offering.name });
      await requestCard.getByRole('combobox', { name: `Session for ${offering.name}` }).click();
      await admin.getByRole('option').filter({ hasText: /.+/ }).last().click();
      await requestCard.getByRole('button', { name: 'Approve and assign' }).click();
      await expect(admin.getByText('Private session approved', { exact: true })).toBeVisible();

      await waitForEmail(organizer.request, organizer.email, /private session request was approved/i);
      await organizer.page.goto('/private-session-requests');
      await expect(organizer.page.getByText('approved', { exact: true })).toBeVisible();
      await expect(
        organizer.page.getByRole('link', { name: 'View scheduled session' }),
      ).toHaveAttribute('href', `/sessions/${requestSession.id}`);
      await adminContext.close();
    });

    await inviteeContext.close();
    await owner.dispose();
  });
});
