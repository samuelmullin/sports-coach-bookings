import { HttpResponse, http } from 'msw';
import { Route, Routes } from 'react-router-dom';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../../test/render';
import { clearGuestCart, readGuestCart } from '../../cart/guest-cart';
import { OfferingDetailPage } from '../OfferingDetailPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const offering = {
  id: 'off-1',
  name: 'Group U11-U14',
  slug: 'group-u11-u14',
  description: 'Technical development for older players.',
  format: 'group',
  duration_minutes: 90,
  default_capacity: 16,
  credit_cost: 1,
  drop_in_price: 4000,
  min_age: 11,
  max_age: 14,
  active: true,
  position: 3,
};

const packs = {
  data: [
    {
      id: 'pack-3',
      name: 'Group U11-U14 3-Session Pack',
      credit_quantity: 3,
      price: 11400,
      validity_days: 180,
      active: true,
      visible_in_portal: true,
      position: 3,
      offering_ids: ['off-1'],
    },
    {
      id: 'pack-5',
      name: 'Group U11-U14 5-Session Pack',
      credit_quantity: 5,
      price: 18000,
      validity_days: 240,
      active: true,
      visible_in_portal: true,
      position: 5,
      offering_ids: ['off-1'],
    },
  ],
  next_cursor: null,
};

function renderOffering() {
  return renderWithProviders(
    <Routes>
      <Route path="/offerings/:offeringId" element={<OfferingDetailPage />} />
      <Route path="/schedule" element={<div>Schedule screen</div>} />
    </Routes>,
    { route: '/offerings/off-1', withAuth: true },
  );
}

function mockOffering() {
  server.use(
    http.get('/api/portal/account', () => new HttpResponse(null, { status: 401 })),
    http.get('/api/portal/catalog/offerings', () =>
      HttpResponse.json({ data: [offering], next_cursor: null }),
    ),
    http.get('/api/portal/catalog/offerings/off-1/packages', () => HttpResponse.json(packs)),
    http.get('/api/portal/policies/offerings/off-1', () => new HttpResponse(null, { status: 404 })),
  );
}

describe('OfferingDetailPage packs', () => {
  it('lists the packs a customer can buy for the offering', async () => {
    mockOffering();
    renderOffering();

    expect(await screen.findByRole('heading', { name: /Group U11-U14/ })).toBeInTheDocument();
    expect(await screen.findByRole('heading', { name: 'Sessions' })).toBeInTheDocument();
    expect(screen.getByText('Single session')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Book now' })).toHaveAttribute(
      'href',
      '/offerings/off-1/schedule',
    );
    expect(screen.getByText('Group U11-U14 3-Session Pack')).toBeInTheDocument();
    expect(screen.getByText(/3 sessions/)).toBeInTheDocument();
    expect(screen.getByText('Group U11-U14 5-Session Pack')).toBeInTheDocument();
    expect(screen.getByText(/5 sessions/)).toBeInTheDocument();
  });

  it('adds a pack to the guest cart', async () => {
    clearGuestCart();
    mockOffering();
    renderOffering();

    const buttons = await screen.findAllByRole('button', { name: 'Add to cart' });
    await userEvent.click(buttons[0]);

    expect(await screen.findByText('Added to cart')).toBeInTheDocument();
    const lines = readGuestCart();
    expect(lines).toHaveLength(1);
    expect(lines[0]).toMatchObject({
      type: 'package',
      ref_id: 'pack-3',
      snapshot: { title: 'Group U11-U14 3-Session Pack' },
    });
  });

  it('still shows the single session option when there are no packs', async () => {
    server.use(
      http.get('/api/portal/account', () => new HttpResponse(null, { status: 401 })),
      http.get('/api/portal/catalog/offerings', () =>
        HttpResponse.json({ data: [offering], next_cursor: null }),
      ),
      http.get('/api/portal/catalog/offerings/off-1/packages', () =>
        HttpResponse.json({ data: [], next_cursor: null }),
      ),
      http.get(
        '/api/portal/policies/offerings/off-1',
        () => new HttpResponse(null, { status: 404 }),
      ),
    );
    renderOffering();

    expect(await screen.findByRole('heading', { name: 'Sessions' })).toBeInTheDocument();
    expect(screen.getByText('Single session')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Book now' })).toHaveAttribute(
      'href',
      '/offerings/off-1/schedule',
    );
  });
});
