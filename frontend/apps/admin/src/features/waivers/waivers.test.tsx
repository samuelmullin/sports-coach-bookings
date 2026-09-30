import { HttpResponse, http } from 'msw';
import { Route, Routes } from 'react-router-dom';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../test/render';
import { MarkdownPreview } from '../shared/MarkdownPreview';
import { WaiversPage } from './WaiversPage';
import { WaiverEditorPage } from './WaiverEditorPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const settings = {
  currency_locked: false,
  tenant: { currency: 'CAD', timezone: 'America/Toronto' },
};

describe('MarkdownPreview', () => {
  it('renders headings, bold and lists', () => {
    renderWithProviders(<MarkdownPreview markdown={'# Title\n\n**bold**\n\n- one\n- two'} />);
    expect(screen.getByRole('heading', { name: 'Title' })).toBeInTheDocument();
    expect(screen.getByText('bold')).toBeInTheDocument();
    expect(screen.getAllByRole('listitem')).toHaveLength(2);
  });
});

describe('WaiversPage', () => {
  it('creates a waiver template (happy path)', async () => {
    server.use(
      http.get('/api/staff/waivers/templates', () =>
        HttpResponse.json({ data: [], next_cursor: null }),
      ),
    );
    server.use(
      http.get('/api/staff/catalog/offerings', () =>
        HttpResponse.json({ data: [], next_cursor: null }),
      ),
    );
    server.use(http.get('/api/staff/settings', () => HttpResponse.json(settings)));
    const post = vi.fn(() =>
      HttpResponse.json(
        { id: 'tmpl-1', name: 'Participation', scope: 'all_bookings' },
        { status: 201 },
      ),
    );
    server.use(http.post('/api/staff/waivers/templates', post));

    renderWithProviders(<WaiversPage />, { route: '/waivers' });
    await userEvent.click(await screen.findByRole('button', { name: 'New waiver' }));
    await userEvent.type(await screen.findByLabelText(/^Name/), 'Participation');
    await userEvent.click(screen.getByRole('button', { name: 'Create template' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(await screen.findByText('Waiver template created')).toBeInTheDocument();
  });

  it('shows a server error', async () => {
    server.use(
      http.get('/api/staff/waivers/templates', () =>
        HttpResponse.json({ data: [], next_cursor: null }),
      ),
    );
    server.use(
      http.get('/api/staff/catalog/offerings', () =>
        HttpResponse.json({ data: [], next_cursor: null }),
      ),
    );
    server.use(http.get('/api/staff/settings', () => HttpResponse.json(settings)));
    server.use(
      http.post('/api/staff/waivers/templates', () =>
        HttpResponse.json(
          {
            error: {
              code: 'invalid',
              message: 'Validation failed',
              details: { fields: { name: ['is taken'] } },
            },
          },
          { status: 422 },
        ),
      ),
    );

    renderWithProviders(<WaiversPage />, { route: '/waivers' });
    await userEvent.click(await screen.findByRole('button', { name: 'New waiver' }));
    await userEvent.type(await screen.findByLabelText(/^Name/), 'Participation');
    await userEvent.click(screen.getByRole('button', { name: 'Create template' }));

    expect(await screen.findByText('is taken')).toBeInTheDocument();
  });
});

describe('WaiverEditorPage', () => {
  it('publishes a new version after confirming re-sign impact', async () => {
    server.use(
      http.get('/api/staff/waivers/templates/:id', () =>
        HttpResponse.json({
          id: 'tmpl-1',
          name: 'Participation',
          require_resign_on_new_version: true,
          scope: 'all_bookings',
        }),
      ),
    );
    server.use(
      http.get('/api/staff/waivers/templates/:templateId/versions', () =>
        HttpResponse.json({
          data: [
            {
              id: 'v1',
              version: 1,
              status: 'published',
              body_markdown: '# Waiver v1',
              waiver_template_id: 'tmpl-1',
              content_sha256: 'x',
            },
          ],
          next_cursor: null,
        }),
      ),
    );
    server.use(
      http.get('/api/staff/waivers/signatures', () =>
        HttpResponse.json({ data: [], next_cursor: null }),
      ),
    );
    server.use(http.get('/api/staff/settings', () => HttpResponse.json(settings)));
    const create = vi.fn(() =>
      HttpResponse.json(
        {
          id: 'v2',
          version: 2,
          status: 'draft',
          body_markdown: '# Waiver v2',
          waiver_template_id: 'tmpl-1',
          content_sha256: 'y',
        },
        { status: 201 },
      ),
    );
    const publish = vi.fn(() =>
      HttpResponse.json({
        id: 'v2',
        version: 2,
        status: 'published',
        body_markdown: '# Waiver v2',
        waiver_template_id: 'tmpl-1',
        content_sha256: 'y',
      }),
    );
    server.use(http.post('/api/staff/waivers/templates/:templateId/versions', create));
    server.use(http.post('/api/staff/waivers/versions/:id/publish', publish));

    renderWithProviders(
      <Routes>
        <Route path="/waivers/:templateId" element={<WaiverEditorPage />} />
      </Routes>,
      { route: '/waivers/tmpl-1' },
    );

    await userEvent.click(await screen.findByRole('button', { name: 'Publish new version' }));
    const dialogDescription = await screen.findByText(/re-sign this waiver/i);
    expect(dialogDescription).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Publish' }));

    await waitFor(() => expect(create).toHaveBeenCalledTimes(1));
    await waitFor(() => expect(publish).toHaveBeenCalledTimes(1));
  });
});
