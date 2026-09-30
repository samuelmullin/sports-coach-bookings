import { HttpResponse, http } from 'msw';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../test/render';
import { GeneralSettingsForm } from './GeneralSettingsForm';
import { TaxRatesSection } from './TaxRatesSection';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const settingsResponse = (currencyLocked = false) => ({
  currency_locked: currencyLocked,
  tenant: {
    id: 'tenant-1',
    name: 'Demo Soccer Club',
    slug: 'demo',
    status: 'active',
    currency: 'CAD',
    timezone: 'America/Toronto',
    contact_email: 'hello@demo.test',
  },
});

describe('GeneralSettingsForm', () => {
  it('saves settings (happy path)', async () => {
    server.use(http.get('/api/staff/settings', () => HttpResponse.json(settingsResponse())));
    const patch = vi.fn(() => HttpResponse.json(settingsResponse()));
    server.use(http.patch('/api/staff/settings', patch));

    renderWithProviders(<GeneralSettingsForm />);

    const name = await screen.findByLabelText(/Business name/);
    await userEvent.clear(name);
    await userEvent.type(name, 'Demo FC');
    await userEvent.click(screen.getByRole('button', { name: 'Save settings' }));

    await waitFor(() => expect(patch).toHaveBeenCalledTimes(1));
    expect(await screen.findByText('Settings saved')).toBeInTheDocument();
  });

  it('maps server field errors inline', async () => {
    server.use(http.get('/api/staff/settings', () => HttpResponse.json(settingsResponse())));
    server.use(
      http.patch('/api/staff/settings', () =>
        HttpResponse.json(
          {
            error: {
              code: 'invalid',
              message: 'Validation failed',
              details: { fields: { name: ['is already taken'] } },
            },
          },
          { status: 422 },
        ),
      ),
    );

    renderWithProviders(<GeneralSettingsForm />);
    await screen.findByLabelText(/Business name/);
    await userEvent.click(screen.getByRole('button', { name: 'Save settings' }));

    expect(await screen.findByText('is already taken')).toBeInTheDocument();
  });

  it('disables the currency selector when locked', async () => {
    server.use(http.get('/api/staff/settings', () => HttpResponse.json(settingsResponse(true))));
    renderWithProviders(<GeneralSettingsForm />);
    expect(await screen.findByLabelText('Currency')).toBeDisabled();
  });
});

describe('TaxRatesSection', () => {
  const rates = {
    data: [{ id: 'tax-1', name: 'HST', rate_bps: 1300, active: true }],
    next_cursor: null,
  };

  it('creates a tax rate (happy path)', async () => {
    server.use(http.get('/api/staff/catalog/tax_rates', () => HttpResponse.json(rates)));
    const post = vi.fn(() =>
      HttpResponse.json({ id: 'tax-2', name: 'GST', rate_bps: 500, active: true }, { status: 201 }),
    );
    server.use(http.post('/api/staff/catalog/tax_rates', post));

    renderWithProviders(<TaxRatesSection />);
    await userEvent.type(await screen.findByLabelText(/^Name/), 'GST');
    await userEvent.type(screen.getByLabelText(/Rate/), '5');
    await userEvent.click(screen.getByRole('button', { name: 'Add rate' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(await screen.findByText('Tax rate added')).toBeInTheDocument();
  });

  it('shows a server error when creation fails', async () => {
    server.use(http.get('/api/staff/catalog/tax_rates', () => HttpResponse.json(rates)));
    server.use(
      http.post('/api/staff/catalog/tax_rates', () =>
        HttpResponse.json(
          {
            error: {
              code: 'invalid',
              message: 'Validation failed',
              details: { fields: { rate_bps: ['is out of range'] } },
            },
          },
          { status: 422 },
        ),
      ),
    );

    renderWithProviders(<TaxRatesSection />);
    await userEvent.type(await screen.findByLabelText(/^Name/), 'GST');
    await userEvent.click(screen.getByRole('button', { name: 'Add rate' }));

    expect(await screen.findByText('is out of range')).toBeInTheDocument();
  });
});
