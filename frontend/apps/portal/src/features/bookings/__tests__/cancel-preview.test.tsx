import { HttpResponse, http } from 'msw';
import { screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { getPortalExtraHandlers } from '../../../api/extra-handlers';
import { renderWithProviders } from '../../../test/render';
import { CancelBookingDialog } from '../CancelBookingDialog';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
beforeEach(() => server.use(...getPortalExtraHandlers()));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const preview = {
  already_cancelled: false,
  booking: {
    id: 'booking-1',
    session_id: 'session-1',
    player_id: 'player-1',
    status: 'confirmed',
    payment_method: 'credits',
  },
  outcome: {
    allowed: true,
    credit_outcome: 'return',
    reason: null,
    refund_amount: null,
  },
};

const cancelled = { ...preview.booking, status: 'cancelled' };

describe('CancelBookingDialog', () => {
  it('shows the outcome preview and cancels the booking (happy path)', async () => {
    server.use(
      http.get('/api/portal/bookings/booking-1/cancel-preview', () => HttpResponse.json(preview)),
    );
    const post = vi.fn(() => HttpResponse.json(cancelled));
    server.use(http.post('/api/portal/bookings/booking-1/cancel', post));

    renderWithProviders(
      <CancelBookingDialog bookingId="booking-1" open onOpenChange={() => undefined} />,
    );

    expect(await screen.findByText('Your sessions will be returned.')).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'Cancel booking' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    expect(await screen.findByText('Booking cancelled')).toBeInTheDocument();
  });

  it('surfaces a server error when cancellation is rejected', async () => {
    server.use(
      http.get('/api/portal/bookings/booking-1/cancel-preview', () => HttpResponse.json(preview)),
    );
    server.use(
      http.post('/api/portal/bookings/booking-1/cancel', () =>
        HttpResponse.json(
          { error: { code: 'too_late', message: 'This booking can no longer be cancelled' } },
          { status: 422 },
        ),
      ),
    );

    renderWithProviders(
      <CancelBookingDialog bookingId="booking-1" open onOpenChange={() => undefined} />,
    );
    await screen.findByText('Your sessions will be returned.');
    await userEvent.click(screen.getByRole('button', { name: 'Cancel booking' }));

    expect(await screen.findByText('This booking can no longer be cancelled')).toBeInTheDocument();
  });
});
