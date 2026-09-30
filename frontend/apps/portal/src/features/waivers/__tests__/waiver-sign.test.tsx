import { HttpResponse, http } from 'msw';
import { Route, Routes } from 'react-router-dom';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { getPortalExtraHandlers } from '../../../api/extra-handlers';
import { renderWithProviders } from '../../../test/render';
import { WaiverSignPage } from '../WaiverSignPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => server.use(...getPortalExtraHandlers()));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const version = {
  id: 'v1',
  waiver_template_id: 't1',
  version: 1,
  body_markdown: '# Participation waiver\nPlease read carefully.',
  status: 'published',
  content_sha256: 'abc123',
};

const signature = {
  id: 'sig-1',
  waiver_version_id: 'v1',
  player_id: 'player-1',
  signer_name_typed: 'Pat Parent',
  consent_checkbox: true,
  signed_at: '2026-10-01T12:00:00Z',
};

function renderSign() {
  return renderWithProviders(
    <Routes>
      <Route path="/players/:playerId/waivers/:versionId/sign" element={<WaiverSignPage />} />
    </Routes>,
    { route: '/players/player-1/waivers/v1/sign' },
  );
}

async function completeForm() {
  await userEvent.type(await screen.findByLabelText(/Type your full name/), 'Pat Parent');
  await userEvent.click(screen.getByRole('checkbox', { name: /I have read and agree/ }));
}

describe('WaiverSignPage', () => {
  it('signs a waiver and sends the content hash (happy path)', async () => {
    server.use(http.get('/api/portal/waivers/versions/v1', () => HttpResponse.json(version)));
    let captured: Record<string, unknown> | undefined;
    const post = vi.fn(async ({ request }: { request: Request }) => {
      captured = (await request.json()) as Record<string, unknown>;
      return HttpResponse.json(signature, { status: 201 });
    });
    server.use(http.post('/api/portal/players/player-1/waivers/v1/sign', post));

    renderSign();
    await completeForm();
    await userEvent.click(screen.getByRole('button', { name: 'Sign waiver' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(captured).toMatchObject({ content_sha256: 'abc123', consent_checkbox: true });
    expect(await screen.findByRole('heading', { name: 'Waiver signed' })).toBeInTheDocument();
  });

  it('shows an inline error on a server field error', async () => {
    server.use(http.get('/api/portal/waivers/versions/v1', () => HttpResponse.json(version)));
    server.use(
      http.post('/api/portal/players/player-1/waivers/v1/sign', () =>
        HttpResponse.json(
          {
            error: {
              code: 'invalid',
              message: 'Invalid signature',
              details: { fields: { signer_name_typed: ['Name does not match the account'] } },
            },
          },
          { status: 422 },
        ),
      ),
    );

    renderSign();
    await completeForm();
    await userEvent.click(screen.getByRole('button', { name: 'Sign waiver' }));

    expect(await screen.findByText('Name does not match the account')).toBeInTheDocument();
  });
});
