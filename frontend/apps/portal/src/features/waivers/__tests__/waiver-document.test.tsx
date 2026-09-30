import { HttpResponse, http } from 'msw';
import { Route, Routes } from 'react-router-dom';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
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
  body_markdown: '# Participation waiver\n\nPlease read carefully.',
  status: 'published',
  content_sha256: 'abc123',
};

function renderSign() {
  return renderWithProviders(
    <Routes>
      <Route path="/players/:playerId/waivers/:versionId/sign" element={<WaiverSignPage />} />
    </Routes>,
    { route: '/players/player-1/waivers/v1/sign' },
  );
}

describe('WaiverSignPage document modal', () => {
  it('opens the waiver body and emails a copy of the version', async () => {
    let body: Record<string, unknown> | undefined;
    server.use(
      http.get('/api/portal/waivers/versions/v1', () => HttpResponse.json(version)),
      http.post('/api/portal/waivers/versions/v1/email', async ({ request }) => {
        body = (await request.json()) as Record<string, unknown>;
        return HttpResponse.json({ status: 'queued', email: body.email }, { status: 202 });
      }),
    );

    renderSign();

    await screen.findByRole('heading', { name: 'Read and sign' });
    await userEvent.click(screen.getByRole('button', { name: /View document/ }));

    expect(await screen.findByRole('heading', { name: 'Waiver' })).toBeInTheDocument();
    expect(screen.getAllByText('Please read carefully.').length).toBeGreaterThan(0);

    await userEvent.type(screen.getByLabelText('Email address'), 'dana@example.com');
    await userEvent.click(screen.getByRole('button', { name: 'Email a copy' }));

    await waitFor(() => expect(body).toEqual({ email: 'dana@example.com' }));
  });
});
