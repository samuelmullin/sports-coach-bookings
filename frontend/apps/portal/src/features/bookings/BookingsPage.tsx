import { useState } from 'react';
import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { CalendarCheck } from 'lucide-react';
import { Badge, Button, Card, CardContent, EmptyState } from '@scb/ui';
import {
  useBookings,
  usePlayers,
  type BookingListItem,
  type PlayerResponse,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { VenueTime, TimezoneNote } from '../shared/VenueTime';
import { usePortalSettings } from '../shared/extras';
import { CancelBookingDialog } from './CancelBookingDialog';
import { RebookDialog } from './RebookDialog';
import { InviteSessionDialog } from './InviteSessionDialog';
import { SessionInvitationsPanel } from './SessionInvitationsPanel';

function readString(
  record: Record<string, unknown> | null | undefined,
  key: string,
): string | undefined {
  const value = record?.[key];
  return typeof value === 'string' ? value : undefined;
}

const STATUS_VARIANT: Record<string, 'success' | 'warning' | 'outline' | 'danger'> = {
  confirmed: 'success',
  held: 'warning',
  cancelled: 'outline',
  attended: 'success',
  no_show: 'danger',
};

export function BookingsPage() {
  const { t } = useTranslation();
  const settings = usePortalSettings();
  const [scope, setScope] = useState<'upcoming' | 'past'>('upcoming');
  const query = useBookings({ scope });
  const playersQuery = usePlayers();

  const bookings = listItems<BookingListItem>(query);
  const players = listItems<PlayerResponse>(playersQuery);
  const playerName = (id: string | null | undefined) => {
    const player = players.find((candidate) => candidate.id === id);
    return player ? `${player.first_name} ${player.last_name}` : 'Player';
  };

  const [cancelId, setCancelId] = useState<string | null>(null);
  const [rebookId, setRebookId] = useState<string | null>(null);
  const [inviteSessionId, setInviteSessionId] = useState<string | null>(null);

  return (
    <div className="flex flex-col gap-4">
      <PageHeader title={t('nav.bookings')} description={t('bookings.subtitle')} />

      <div className="flex gap-2">
        <Button
          variant={scope === 'upcoming' ? 'primary' : 'outline'}
          size="sm"
          onClick={() => setScope('upcoming')}
        >
          Upcoming
        </Button>
        <Button
          variant={scope === 'past' ? 'primary' : 'outline'}
          size="sm"
          onClick={() => setScope('past')}
        >
          Past
        </Button>
      </div>

      <TimezoneNote timezone={settings.timezone} />

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {bookings.length === 0 ? (
          <EmptyState
            icon={<CalendarCheck className="h-8 w-8" />}
            title={t('empty.bookings')}
            description="Book a session from the schedule to get started."
            action={
              <Button asChild>
                <Link to="/schedule">Browse schedule</Link>
              </Button>
            }
          />
        ) : (
          <ul className="flex flex-col gap-3">
            {bookings.map((item) => (
              <li key={item.booking.id}>
                <BookingCard
                  item={item}
                  playerName={playerName(item.booking.player_id)}
                  timezone={settings.timezone}
                  onCancel={() => setCancelId(item.booking.id)}
                  onRebook={() => setRebookId(item.booking.id)}
                  onInvite={() => setInviteSessionId(item.booking.session_id)}
                />
              </li>
            ))}
          </ul>
        )}
      </QueryState>

      <SessionInvitationsPanel />

      {cancelId ? (
        <CancelBookingDialog
          bookingId={cancelId}
          open={cancelId !== null}
          onOpenChange={(open) => !open && setCancelId(null)}
        />
      ) : null}
      {rebookId ? (
        <RebookDialog
          bookingId={rebookId}
          open={rebookId !== null}
          onOpenChange={(open) => !open && setRebookId(null)}
        />
      ) : null}
      {inviteSessionId ? (
        <InviteSessionDialog
          sessionId={inviteSessionId}
          open
          onOpenChange={(open) => !open && setInviteSessionId(null)}
        />
      ) : null}
    </div>
  );
}

function BookingCard({
  item,
  playerName,
  timezone,
  onCancel,
  onRebook,
  onInvite,
}: {
  item: BookingListItem;
  playerName: string;
  timezone: string;
  onCancel: () => void;
  onRebook: () => void;
  onInvite: () => void;
}) {
  const booking = item.booking;
  const session = item.session as Record<string, unknown> | null;
  const offering = item.offering as Record<string, unknown> | null;
  const startsAt = readString(session, 'starts_at');
  const title = readString(offering, 'name') ?? 'Session';
  const canAct = booking.status === 'confirmed' || booking.status === 'held';
  const canInvite =
    canAct &&
    offering?.allow_invite_reservations === true &&
    Number(session?.seats_left ?? 0) > 0 &&
    booking.player_id != null;

  return (
    <Card data-testid="booking-card">
      <CardContent className="flex flex-col gap-3 pt-4">
        <div className="flex flex-wrap items-start justify-between gap-2">
          <div className="flex flex-col gap-0.5">
            <h3 className="font-medium">{title}</h3>
            <span className="text-sm text-muted-foreground">{playerName}</span>
            {startsAt ? (
              <VenueTime
                instant={startsAt}
                timezone={timezone}
                className="text-sm text-muted-foreground"
              />
            ) : null}
          </div>
          <Badge variant={STATUS_VARIANT[booking.status] ?? 'outline'}>{booking.status}</Badge>
        </div>

        <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
          <span>Paid with {booking.payment_method}</span>
          {booking.credits_used && booking.credits_used > 0 ? (
            <span>· {booking.credits_used} sessions used</span>
          ) : null}
        </div>

        {booking.status === 'held' && booking.hold_expires_at ? (
          <p className="text-sm text-amber-700">
            Held until <VenueTime instant={booking.hold_expires_at} timezone={timezone} />
          </p>
        ) : null}

        {canAct ? (
          <div className="flex flex-wrap gap-2">
            {canInvite ? (
              <Button size="sm" onClick={onInvite}>
                Invite someone
              </Button>
            ) : null}
            <Button size="sm" variant="outline" onClick={onRebook}>
              Rebook
            </Button>
            <Button size="sm" variant="ghost" className="text-danger" onClick={onCancel}>
              Cancel
            </Button>
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}
