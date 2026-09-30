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
beforeEach(() =>
  server.use(
    ...getPortalExtraHandlers(),
    http.get('*/api/portal/branding', () => HttpResponse.json(mockBrandings.demo)),
  ),
);
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const anonymousAccount = () =>
  HttpResponse.json({ error: { code: 'forbidden', message: 'No session' } }, { status: 403 });

async function fillRequiredFields() {
  await userEvent.type(await screen.findByLabelText('First name'), 'Dana');
  await userEvent.type(screen.getByLabelText('Last name'), 'Reyes');
  await userEvent.type(screen.getByLabelText('Email'), 'dana@example.com');
  await userEvent.type(screen.getByLabelText('Password'), 'a very long password');
  await userEvent.type(screen.getByLabelText('Confirm password'), 'a very long password');
  await userEvent.click(screen.getByLabelText('I accept the terms of service'));
  await userEvent.click(screen.getByLabelText('I accept the privacy policy'));
}

describe('RegisterPage phone input', () => {
  it('submits the selected country and national number', async () => {
    let body: Record<string, unknown> | undefined;
    server.use(
      http.get('*/api/portal/account', anonymousAccount),
      http.post('*/api/portal/registrations', async ({ request }) => {
        body = (await request.json()) as Record<string, unknown>;
        return HttpResponse.json(
          { customer_user: { id: 'u1' }, household: { id: 'h1' } },
          { status: 201 },
        );
      }),
    );

    renderWithProviders(
      <BrandingProvider>
        <RegisterPage />
      </BrandingProvider>,
      { withAuth: true },
    );
    await fillRequiredFields();

    await userEvent.selectOptions(screen.getByLabelText('Country calling code'), 'GB');
    await userEvent.type(screen.getByLabelText('Phone'), '7911123456');
    await userEvent.click(screen.getByRole('button', { name: 'Create account' }));

    await waitFor(() => expect(body).toBeDefined());
    expect(body).toMatchObject({ phone: '7911123456', phone_country: 'GB' });
  });

  it('shows the friendly error for an invalid number and does not submit', async () => {
    const post = vi.fn();
    server.use(
      http.get('*/api/portal/account', anonymousAccount),
      http.post('*/api/portal/registrations', () => {
        post();
        return HttpResponse.json({}, { status: 201 });
      }),
    );

    renderWithProviders(
      <BrandingProvider>
        <RegisterPage />
      </BrandingProvider>,
      { withAuth: true },
    );
    await fillRequiredFields();

    await userEvent.type(screen.getByLabelText('Phone'), '123');
    await userEvent.click(screen.getByRole('button', { name: 'Create account' }));

    expect(
      await screen.findByText('Enter a valid phone number for the selected country.'),
    ).toBeInTheDocument();
    expect(post).not.toHaveBeenCalled();
  });
});
