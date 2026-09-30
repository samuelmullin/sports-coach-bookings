import { useMemo, useState } from 'react';
import { Link, useLocation, useParams } from 'react-router-dom';
import { ArrowLeft, CalendarPlus, CheckCircle2, XCircle } from 'lucide-react';
import { Badge, Button, Card, CardContent, RadioGroup, useToast } from '@scb/ui';
import { useQueryClient } from '@tanstack/react-query';
import {
  bookingsQueryKey,
  creditsQueryKey,
  useCreateBooking,
  useCredits,
  useHouseholdWaiverStatus,
  useOfferings,
  usePlayers,
  useSessions,
  type CreditBalance,
  type HouseholdWaiverStatusResponse,
  type OfferingResponse,
  type PlayerResponse,
  type SessionListItem,
} from '../../api/endpoints';
import { errorCode, errorMessage, listItems } from '../shared/api-utils';
import { friendlyError } from '../shared/errors';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { PlayerSelect } from '../shared/PlayerSelect';
import { VenueTime, TimezoneNote } from '../shared/VenueTime';
import { usePortalSettings } from '../shared/extras';
import { isAgeEligible } from '../shared/age';

function isoDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function icsDataUrl(item: SessionListItem, title: string): string | undefined {
  const startsAt = item.session?.starts_at;
  const endsAt = item.session?.ends_at;
  if (!startsAt || !endsAt) return undefined;
  const toIcs = (value: string) =>
    new Date(value).toISOString().replace(/[-:]/g, '').split('.')[0] + 'Z';
  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'BEGIN:VEVENT',
    `DTSTART:${toIcs(startsAt)}`,
    `DTEND:${toIcs(endsAt)}`,
    `SUMMARY:${title}`,
    item.venue?.name ? `LOCATION:${item.venue.name}` : '',
    'END:VEVENT',
    'END:VCALENDAR',
  ].filter(Boolean);
  return `data:text/calendar;charset=utf-8,${encodeURIComponent(lines.join('\r\n'))}`;
}

export function BookingFlowPage() {
  const { sessionId = '' } = useParams<{ sessionId: string }>();
  const location = useLocation();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const settings = usePortalSettings();

  const stateItem = (location.state as { session?: SessionListItem } | null)?.session;

  const range = useMemo(() => {
    const from = new Date();
    from.setDate(from.getDate() - 1);
    const to = new Date();
    to.setDate(to.getDate() + 180);
    return { from: isoDate(from), to: isoDate(to) };
  }, []);

  const sessionsQuery = useSessions({ from: range.from, to: range.to });
  const playersQuery = usePlayers();
  const creditsQuery = useCredits();
  const waiversQuery = useHouseholdWaiverStatus();
  const createBooking = useCreateBooking();

  const players = listItems<PlayerResponse>(playersQuery);
  const credits = listItems<CreditBalance>(creditsQuery);
  const offerings = listItems<OfferingResponse>(useOfferings());
  const waiverStatus = waiversQuery.data?.data as HouseholdWaiverStatusResponse | undefined;

  const item =
    stateItem ??
    listItems<SessionListItem>(sessionsQuery).find(
      (candidate) => candidate.session?.id === sessionId,
    ) ??
    undefined;

  const [playerId, setPlayerId] = useState<string | undefined>();
  const [method, setMethod] = useState<'credits' | 'paid'>('credits');
  const [confirmed, setConfirmed] = useState(false);

  const player = players.find((candidate) => candidate.id === playerId);
  const offering = item?.offering;
  const offeringFull = offerings.find((candidate) => candidate.id === offering?.id);
  const session = item?.session;

  const eligibleCreditTotal = credits
    .filter((entry) => entry.amount > 0)
    .filter((entry) => entry.offering_id === offering?.id || entry.offering_id === 'any')
    .reduce((sum, entry) => sum + entry.amount, 0);

  const waiverEntry = waiverStatus?.players.find((entry) => entry.player_id === playerId);
  const requiredWaivers = waiverEntry?.waivers.filter((waiver) => waiver.required) ?? [];
  const waiversSigned =
    requiredWaivers.length === 0 || requiredWaivers.every((waiver) => waiver.signed);
  const hasContacts = (player?.emergency_contacts?.length ?? 0) > 0;
  const ageOk = player ? isAgeEligible(player, offering?.min_age, offering?.max_age) : false;
  const seatsLeft = item?.seats_left ?? session?.seats_left ?? 0;
  const bookable = item?.bookable ?? false;

  const hasCredits = eligibleCreditTotal > 0;

  const canSubmit =
    Boolean(player) && bookable && seatsLeft > 0 && ageOk && waiversSigned && hasContacts;

  const checks = [
    { label: 'Age eligible', ok: Boolean(player) && ageOk, fix: `/players/${playerId}` },
    {
      label: 'Emergency contact on file',
      ok: hasContacts,
      fix: `/players/${playerId}?tab=contacts`,
    },
    {
      label: 'Required waivers signed',
      ok: waiversSigned,
      fix: `/players/${playerId}?tab=waivers`,
    },
    { label: 'Seats available', ok: seatsLeft > 0, fix: '/schedule' },
  ];

  const onSubmit = async () => {
    if (!playerId || !session?.id) return;
    try {
      const result = await createBooking.mutateAsync({
        data: { player_id: playerId, session_id: session.id, method },
      });
      await queryClient.invalidateQueries({ queryKey: bookingsQueryKey() });
      await queryClient.invalidateQueries({ queryKey: creditsQueryKey() });
      void result;
      toast({ title: 'Booking confirmed', variant: 'success' });
      setConfirmed(true);
    } catch (error) {
      toast({
        title: friendlyError(errorCode(error), errorMessage(error)),
        variant: 'danger',
      });
    }
  };

  if (confirmed) {
    const title = offering?.name ?? 'Session';
    const ics = item ? icsDataUrl(item, title) : undefined;
    return (
      <div className="flex flex-col items-center gap-4 py-8 text-center">
        <CheckCircle2 className="h-12 w-12 text-green-600" aria-hidden="true" />
        <h1 className="text-xl font-semibold">You're booked!</h1>
        <p className="text-sm text-muted-foreground">
          {player?.first_name} is booked into {title}.
        </p>
        <div className="flex flex-wrap justify-center gap-2">
          {ics ? (
            <Button asChild variant="outline">
              <a href={ics} download="session.ics">
                <CalendarPlus className="h-4 w-4" aria-hidden="true" /> Add to calendar
              </a>
            </Button>
          ) : null}
          <Button asChild>
            <Link to="/bookings">View my bookings</Link>
          </Button>
        </div>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <Button asChild variant="ghost" size="sm" className="self-start">
        <Link to="/schedule">
          <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Back to schedule
        </Link>
      </Button>

      <QueryState
        loading={sessionsQuery.isLoading || playersQuery.isLoading}
        error={sessionsQuery.isError ? errorMessage(sessionsQuery.error) : undefined}
        onRetry={() => void sessionsQuery.refetch()}
      >
        {!item || !session ? (
          <p className="text-sm text-muted-foreground">This session is no longer available.</p>
        ) : (
          <>
            <PageHeader
              title={`Book ${offering?.name ?? 'session'}`}
              description={
                session.starts_at ? (
                  <VenueTime
                    instant={session.starts_at}
                    timezone={item.venue?.timezone ?? settings.timezone}
                  />
                ) : undefined
              }
            />
            <TimezoneNote timezone={item.venue?.timezone ?? settings.timezone} />

            <Card>
              <CardContent className="flex flex-col gap-3 pt-4">
                <label className="flex flex-col gap-1 text-sm">
                  <span className="font-medium">Choose a player</span>
                  <PlayerSelect
                    players={players}
                    value={playerId}
                    onChange={setPlayerId}
                    placeholder="Select a player"
                  />
                </label>
                {players.length === 0 ? (
                  <p className="text-sm text-muted-foreground">
                    <Link className="text-primary hover:underline" to="/players">
                      Add a player
                    </Link>{' '}
                    to book this session.
                  </p>
                ) : null}

                {player ? (
                  <ul className="flex flex-col gap-1.5">
                    {checks.map((check) => (
                      <li key={check.label} className="flex items-center gap-2 text-sm">
                        {check.ok ? (
                          <CheckCircle2 className="h-4 w-4 text-green-600" aria-hidden="true" />
                        ) : (
                          <XCircle className="h-4 w-4 text-amber-600" aria-hidden="true" />
                        )}
                        <span className={check.ok ? '' : 'text-muted-foreground'}>
                          {check.label}
                        </span>
                        {!check.ok ? (
                          <Link
                            className="ml-auto text-xs font-medium text-primary hover:underline"
                            to={check.fix}
                          >
                            Fix
                          </Link>
                        ) : null}
                      </li>
                    ))}
                  </ul>
                ) : null}
              </CardContent>
            </Card>

            <Card>
              <CardContent className="flex flex-col gap-3 pt-4">
                <h2 className="text-sm font-medium">Payment method</h2>
                <RadioGroup
                  label="Payment method"
                  value={method}
                  onValueChange={(value) => setMethod(value as 'credits' | 'paid')}
                  options={[
                    {
                      value: 'credits',
                      label: hasCredits
                        ? `Use sessions (${eligibleCreditTotal} available)`
                        : 'Use sessions (none available)',
                      disabled: !hasCredits,
                    },
                    { value: 'paid', label: 'Pay as a drop-in' },
                  ]}
                />
                {!hasCredits ? (
                  <p className="text-xs text-muted-foreground">
                    No eligible sessions. You can pay for a drop-in or{' '}
                    <Link className="text-primary hover:underline" to="/packages">
                      buy a package
                    </Link>
                    .
                  </p>
                ) : null}
              </CardContent>
            </Card>

            <Card>
              <CardContent className="flex flex-col gap-2 pt-4 text-sm">
                <h2 className="font-medium">Summary</h2>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Player</span>
                  <span>
                    {player ? `${player.first_name} ${player.last_name}` : 'Not selected'}
                  </span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">Method</span>
                  <span>{method === 'credits' ? 'Sessions' : 'Drop-in'}</span>
                </div>
                {method === 'credits' && offeringFull?.credit_cost ? (
                  <div className="flex justify-between">
                    <span className="text-muted-foreground">Sessions</span>
                    <Badge variant="accent">{offeringFull.credit_cost}</Badge>
                  </div>
                ) : null}
                {method === 'paid' ? (
                  <p className="text-xs text-muted-foreground">
                    Drop-in pricing is confirmed at checkout.
                  </p>
                ) : null}
                <p className="text-xs text-muted-foreground">
                  By booking you agree to the club's cancellation policy.
                </p>
              </CardContent>
            </Card>

            <div className="flex flex-wrap gap-2">
              <Button
                onClick={() => void onSubmit()}
                disabled={!canSubmit || createBooking.isPending}
              >
                {createBooking.isPending ? 'Booking…' : 'Confirm booking'}
              </Button>
              <Button asChild variant="outline">
                <Link to="/schedule">Cancel</Link>
              </Button>
            </div>
          </>
        )}
      </QueryState>
    </div>
  );
}
