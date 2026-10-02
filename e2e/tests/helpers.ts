import { expect, type APIRequestContext, type Page } from '@playwright/test';

export const SEEDED = {
  parent: { email: 'parent@example.com', password: 'demo-customer-password' },
  owner: { email: 'owner@sportscoachbookings.com', password: 'demo-owner-password' },
  coach: { email: 'coach@sportscoachbookings.com', password: 'demo-coach-password' },
} as const;

export const PASSWORD = 'a long e2e password 123';

let counter = 0;

/** A unique, valid email so journeys never collide across runs or retries. */
export function uniqueEmail(prefix = 'e2e'): string {
  counter += 1;
  return `${prefix}-${Date.now()}-${counter}@example.com`;
}

interface MailboxMessage {
  to: string[];
  subject: string;
  html_body: string | null;
  text_body: string | null;
}

/**
 * Polls the dev mailbox (Swoosh local adapter) for the newest message to
 * `to` whose subject matches. Oban delivers asynchronously, hence the poll.
 */
export async function waitForEmail(
  request: APIRequestContext,
  to: string,
  subject: RegExp,
): Promise<MailboxMessage> {
  let found: MailboxMessage | undefined;
  await expect
    .poll(
      async () => {
        const response = await request.get('/dev/mailbox/json');
        const body = (await response.json()) as { data: MailboxMessage[] };
        found = body.data.find((m) => m.to.includes(to) && subject.test(m.subject));
        return found?.subject ?? null;
      },
      { message: `email to ${to} matching ${subject}`, timeout: 20_000 },
    )
    .not.toBeNull();
  return found as MailboxMessage;
}

/** First absolute-or-relative link in an email body that matches `pattern`. */
export function linkFrom(message: MailboxMessage, pattern: RegExp): string {
  const body = `${message.text_body ?? ''}\n${message.html_body ?? ''}`;
  const match = body.match(pattern);
  if (!match) throw new Error(`no link matching ${pattern} in "${message.subject}"`);
  return match[0].replace(/&amp;/g, '&');
}

export async function loginPortal(page: Page, email: string, password: string) {
  await page.goto('/login');
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', { name: 'Sign in' }).click();
  await expect(page.getByRole('button', { name: 'Sign out' })).toBeVisible();
}

export async function loginAdmin(page: Page, email: string, password: string) {
  await page.goto('/admin/login');
  await page.getByLabel('Email').fill(email);
  await page.getByLabel('Password').fill(password);
  await page.getByRole('button', { name: /sign in/i }).click();
  await expect(page).not.toHaveURL(/\/login/);
}

/** Picks an option from one of the app's custom (non-native) comboboxes. */
export async function pickOption(page: Page, combobox: string, option: string | RegExp) {
  await page.getByRole('combobox', { name: combobox }).click();
  await page.getByRole('option', { name: option }).click();
}

/** An ISO birth date for a player who is `years` old today (plus ~6 months). */
export function dobForAge(years: number): string {
  const date = new Date();
  date.setFullYear(date.getFullYear() - years);
  date.setMonth(date.getMonth() - 6);
  return date.toISOString().slice(0, 10);
}
