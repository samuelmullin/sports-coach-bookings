import { HttpResponse, http } from 'msw';
import { Route, Routes } from 'react-router-dom';
import { screen } from '@testing-library/react';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../../test/render';
import { PackageDetailPage } from '../PackageDetailPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const offering = { id: 'off-1', name: 'Group U11-U14' };

const scopedPackage = {
  id: 'pack-1',
  name: 'Group U11-U14 5-Session Pack',
  description: 'Five sessions for older players.',
  credit_quantity: 5,
  price: 18000,
  validity_days: 240,
  active: true,
  visible_in_portal: true,
  position: 5,
  offering_ids: ['off-1'],
};

const globalPackage = {
  id: 'pack-2',
  name: '20-Session Pack',
  description: 'Any offering.',
  credit_quantity: 20,
  price: 160000,
  validity_days: 365,
  active: true,
  visible_in_portal: true,
  position: 20,
  offering_ids: [],
};

function mockCatalog(packagePayload: unknown) {
  server.use(
    http.get('/api/portal/account', () => new HttpResponse(null, { status: 401 })),
    http.get('/api/portal/catalog/packages', () =>
      HttpResponse.json({ data: [packagePayload], next_cursor: null }),
    ),
    http.get('/api/portal/catalog/offerings', () =>
      HttpResponse.json({ data: [offering], next_cursor: null }),
    ),
  );
}

function renderPackage(packageId: string) {
  return renderWithProviders(
    <Routes>
      <Route path="/packages/:packageId" element={<PackageDetailPage />} />
    </Routes>,
    { route: `/packages/${packageId}`, withAuth: true },
  );
}

describe('PackageDetailPage scope', () => {
  it('shows the offerings a package is valid for', async () => {
    mockCatalog(scopedPackage);
    renderPackage('pack-1');

    expect(await screen.findByText('Valid for: Group U11-U14')).toBeInTheDocument();
  });

  it('shows any offering when the package is global', async () => {
    mockCatalog(globalPackage);
    renderPackage('pack-2');

    expect(await screen.findByText('Any offering')).toBeInTheDocument();
  });
});
