import { HttpResponse, http } from 'msw';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { getPortalExtraHandlers } from '../../../api/extra-handlers';
import { renderWithProviders } from '../../../test/render';
import { PrivacySection } from '../PrivacySection';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => server.use(...getPortalExtraHandlers()));
afterEach(() => {
  server.resetHandlers();
  vi.restoreAllMocks();
});
afterAll(() => server.close());

async function openDialog() {
  await userEvent.click(screen.getByRole('button', { name: 'Delete my account' }));
  return screen.findByRole('dialog', { name: 'Delete your account?' });
}

async function fillAndSubmit(password: string, confirm = 'ERASE') {
  await userEvent.type(screen.getByLabelText(/Your password/), password);
  await userEvent.type(screen.getByLabelText(/Type ERASE to confirm/), confirm);
  await userEvent.click(screen.getByRole('button', { name: 'Permanently delete' }));
}

describe('PrivacySection', () => {
  it('offers the export as a file download', () => {
    renderWithProviders(<PrivacySection />);

    const link = screen.getByRole('link', { name: /Download my data/ });
    expect(link).toHaveAttribute('href', '/api/portal/account/export');
    expect(link).toHaveAttribute('download', 'household-data.json');
  });

  it('requires the exact confirmation word before calling the server', async () => {
    const erase = vi.fn(() => HttpResponse.json({ players: 0, accounts: 1 }));
    server.use(http.post('/api/portal/account/erase', erase));

    renderWithProviders(<PrivacySection />);
    await openDialog();
    await fillAndSubmit('secret password', 'erase');

    expect(await screen.findByText('Type ERASE to confirm', { selector: 'p' })).toBeInTheDocument();
    expect(erase).not.toHaveBeenCalled();
  });

  it('shows a wrong password next to the field', async () => {
    server.use(
      http.post('/api/portal/account/erase', () =>
        HttpResponse.json(
          { error: { code: 'invalid_password', message: 'Forbidden', details: {} } },
          { status: 403 },
        ),
      ),
    );

    renderWithProviders(<PrivacySection />);
    await openDialog();
    await fillAndSubmit('wrong password');

    expect(await screen.findByText('That password is incorrect.')).toBeInTheDocument();
  });

  it('explains what blocks the erasure in plain language', async () => {
    server.use(
      http.post('/api/portal/account/erase', () =>
        HttpResponse.json(
          {
            error: {
              code: 'erasure_blocked',
              message: 'Conflict',
              details: { reasons: ['upcoming_bookings', 'pending_orders'] },
            },
          },
          { status: 409 },
        ),
      ),
    );

    renderWithProviders(<PrivacySection />);
    await openDialog();
    await fillAndSubmit('secret password');

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent('You have upcoming bookings. Cancel them first.');
    expect(alert).toHaveTextContent('You have an unpaid order. Finish or cancel it first.');
  });

  it('leaves the app once the household is erased', async () => {
    const assign = vi.fn();
    vi.stubGlobal('location', { ...window.location, assign });
    server.use(
      http.post('/api/portal/account/erase', () => HttpResponse.json({ players: 1, accounts: 1 })),
    );

    renderWithProviders(<PrivacySection />);
    await openDialog();
    await fillAndSubmit('secret password');

    await waitFor(() => expect(assign).toHaveBeenCalledWith('/login'));
    vi.unstubAllGlobals();
  });
});
