import { HttpResponse, http } from 'msw';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { mockBrandings } from '@scb/mocks';
import { getPortalExtraHandlers } from '../../../api/extra-handlers';
import { renderWithProviders } from '../../../test/render';
import { BrandingProvider } from '../../../theme/branding';
import { RegisterPage } from '../RegisterPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => server.use(...getPortalExtraHandlers()));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const anonymousAccount = () =>
  HttpResponse.json({ error: { code: 'forbidden', message: 'No session' } }, { status: 403 });

const terms = {
  id: 'doc-1',
  kind: 'terms',
  title: 'Terms of Service',
  body_markdown: '# Terms of Service\n\nBe kind to each other.',
  version: 1,
  active: true,
};

describe('RegisterPage legal documents', () => {
  it('opens the terms modal, renders the body, and prints', async () => {
    const print = vi.spyOn(window, 'print').mockImplementation(() => {});
    server.use(
      http.get('*/api/portal/account', anonymousAccount),
      http.get('*/api/portal/branding', () => HttpResponse.json(mockBrandings.demo)),
      http.get('*/api/portal/documents/terms', () => HttpResponse.json(terms)),
    );

    renderWithProviders(
      <BrandingProvider>
        <RegisterPage />
      </BrandingProvider>,
      { withAuth: true },
    );

    await userEvent.click(await screen.findByRole('link', { name: 'terms of service' }));

    expect(await screen.findAllByText('Be kind to each other.')).not.toHaveLength(0);
    await userEvent.click(screen.getByRole('button', { name: /Print/ }));
    expect(print).toHaveBeenCalledTimes(1);

    print.mockRestore();
  });

  it('emails a copy to the address an anonymous viewer enters', async () => {
    let body: Record<string, unknown> | undefined;
    server.use(
      http.get('*/api/portal/account', anonymousAccount),
      http.get('*/api/portal/branding', () => HttpResponse.json(mockBrandings.demo)),
      http.get('*/api/portal/documents/terms', () => HttpResponse.json(terms)),
      http.post('*/api/portal/documents/terms/email', async ({ request }) => {
        body = (await request.json()) as Record<string, unknown>;
        return HttpResponse.json({ status: 'queued', email: body.email }, { status: 202 });
      }),
    );

    renderWithProviders(
      <BrandingProvider>
        <RegisterPage />
      </BrandingProvider>,
      { withAuth: true },
    );

    await userEvent.click(await screen.findByRole('link', { name: 'terms of service' }));
    await screen.findAllByText('Be kind to each other.');

    await userEvent.type(screen.getByLabelText('Email address'), 'dana@example.com');
    await userEvent.click(screen.getByRole('button', { name: 'Email a copy' }));

    await waitFor(() => expect(body).toEqual({ email: 'dana@example.com' }));
    expect(await screen.findByText('A copy was sent to dana@example.com')).toBeInTheDocument();
  });
});
