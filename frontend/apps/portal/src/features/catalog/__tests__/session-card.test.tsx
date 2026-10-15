import { screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { SessionListItem } from '../../../api/endpoints';
import { renderWithProviders } from '../../../test/render';
import { SessionCard } from '../SessionCard';

const item = {
  bookable: true,
  already_booked: false,
  seats_left: 4,
  offering: { id: 'off-1', name: 'Group U8-U10', format: 'group', default_capacity: 12 },
  session: {
    id: 'session-1',
    offering_id: 'off-1',
    starts_at: '2026-10-20T21:00:00Z',
    ends_at: '2026-10-20T22:00:00Z',
    capacity: 12,
    seats_left: 4,
    status: 'scheduled',
  },
  venue: { id: 'venue-1', name: 'Harbour Dome', timezone: 'America/Toronto' },
  coaches: [],
} as unknown as SessionListItem;

function renderCard(canBook: boolean, creditCost = 1) {
  return renderWithProviders(
    <SessionCard
      item={item}
      timezone="America/Toronto"
      canBook={canBook}
      creditCost={creditCost}
      dropInPrice={3500}
    />,
  );
}

describe('SessionCard', () => {
  // The same action must read the same whether or not the visitor is signed in
  // ("Book" vs "Book now", outline vs filled, used to differ).
  it('labels the booking action "Book" for signed-in and signed-out visitors', () => {
    const signedIn = renderCard(true);
    expect(screen.getByRole('link', { name: 'Book' })).toHaveAttribute('href', '/book/session-1');
    signedIn.unmount();

    renderCard(false);
    expect(screen.getByRole('link', { name: 'Book' })).toHaveAttribute(
      'href',
      '/offerings/off-1/schedule',
    );
    expect(screen.queryByRole('link', { name: 'Book now' })).not.toBeInTheDocument();
  });

  it('says what the session cost means rather than showing a bare count', () => {
    const one = renderCard(true, 1);
    expect(screen.getByText('Uses 1 session')).toBeInTheDocument();
    one.unmount();

    renderCard(true, 2);
    expect(screen.getByText('Uses 2 sessions')).toBeInTheDocument();
  });
});
