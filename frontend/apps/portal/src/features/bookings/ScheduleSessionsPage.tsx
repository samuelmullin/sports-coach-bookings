import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, CalendarDays, CheckCircle2, List, XCircle } from 'lucide-react';
import { useQueryClient } from '@tanstack/react-query';
import {
  Button,
  Calendar,
  Card,
  CardContent,
  Checkbox,
  EmptyState,
  RadioGroup,
  Select,
  formatInZone,
  useToast,
} from '@scb/ui';
import type { CalendarEvent } from '@scb/ui';
import {
  bookingsQueryKey,
  creditsQueryKey,
  useCreateBooking,
  useCredits,
  useOfferings,
  usePlayers,
  useSessions,
  type CreditBalance,
  type OfferingResponse,
  type PlayerResponse,
  type SessionListItem,
} from '../../api/endpoints';
import { errorCode, errorMessage, listItems, responseData } from '../shared/api-utils';
import { friendlyError } from '../shared/errors';
import { firstEventDate } from '../shared/calendarAnchor';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { PlayerSelect } from '../shared/PlayerSelect';
import { Money } from '../shared/Money';
import { VenueTime, TimezoneNote } from '../shared/VenueTime';
import { usePortalSettings } from '../shared/extras';
import { isAgeEligible } from '../shared/age';
import { useAddToCart } from '../cart/useCart';

function isoDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

interface BookingResult {
  sessionId: string;
  label: string;
  ok: boolean;
  message?: string;
}

/**
 * Multi-session scheduling for a single offering.
 *
 * The customer picks a player, multi-selects upcoming sessions from a list or
 * calendar, then either spends credits (one confirmed booking per session) or
 * reserves drop-ins by holding each session and dropping the holds in the cart.
 * "I'll choose dates later" defers to the credits (or packages) page.
 */
export function ScheduleSessionsPage() {
  const { offeringId = '' } = useParams<{ offeringId: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const settings = usePortalSettings();

  const [playerId, setPlayerId] = useState<string | undefined>();
  const [method, setMethod] = useState<'credits' | 'paid' | undefined>();
  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [view, setView] = useState<'list' | 'calendar'>('list');
  const [results, setResults] = useState<BookingResult[] | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const range = useMemo(() => {
    const from = new Date();
    const to = new Date();
    to.setDate(to.getDate() + 90);
    return { from: isoDate(from), to: isoDate(to) };
  }, []);

  const sessionsQuery = useSessions({
    offering_id: offeringId,
    from: range.from,
    to: range.to,
    player_id: playerId,
  });
  const playersQuery = usePlayers();
  const creditsQuery = useCredits();
  const offeringsQuery = useOfferings();
  const createBooking = useCreateBooking();
  const addToCart = useAddToCart();

  const players = listItems<PlayerResponse>(playersQuery);
  const credits = listItems<CreditBalance>(creditsQuery);
  const offerings = listItems<OfferingResponse>(offeringsQuery);
  const sessions = listItems<SessionListItem>(sessionsQuery);

  const offering = offerings.find((candidate) => candidate.id === offeringId);
  const player = players.find((candidate) => candidate.id === playerId);

  useEffect(() => {
    setSelectedIds([]);
    setResults(null);
  }, [offeringId]);

  const eligibleCreditTotal = credits
    .filter((entry) => entry.amount > 0)
    .filter((entry) => entry.offering_id === offeringId || entry.offering_id === 'any')
    .reduce((sum, entry) => sum + entry.amount, 0);
  const hasCredits = eligibleCreditTotal > 0;
  const effectiveMethod: 'credits' | 'paid' = method ?? (hasCredits ? 'credits' : 'paid');

  const selectableSessions = useMemo(
    () =>
      sessions.filter((item) => {
        const id = item.session?.id;
        if (!id || !item.session?.starts_at || item.already_booked) return false;
        if (item.bookable === false) return false;
        return (item.seats_left ?? item.session?.seats_left ?? 0) > 0;
      }),
    [sessions],
  );

  const selectedSessions = useMemo(
    () => selectableSessions.filter((item) => selectedIds.includes(item.session?.id ?? '')),
    [selectableSessions, selectedIds],
  );

  const timezone = useMemo(() => {
    const zone = selectableSessions.find((item) => item.venue?.timezone)?.venue?.timezone;
    return zone ?? settings.timezone;
  }, [selectableSessions, settings.timezone]);

  const ageOk = player ? isAgeEligible(player, offering?.min_age, offering?.max_age) : false;
  const withinCredits = effectiveMethod !== 'credits' || selectedIds.length <= eligibleCreditTotal;
  const canConfirm =
    Boolean(playerId) && selectedIds.length > 0 && withinCredits && ageOk && !submitting;

  const sessionLabel = (item: SessionListItem): string => {
    const startsAt = item.session?.starts_at;
    if (!startsAt) return 'Session';
    return formatInZone(startsAt, item.venue?.timezone ?? timezone, 'EEE MMM d, h:mm a');
  };

  const toggle = (id: string) => {
    setSelectedIds((current) =>
      current.includes(id) ? current.filter((value) => value !== id) : [...current, id],
    );
  };

  const calendarEvents: CalendarEvent[] = selectableSessions
    .filter((item) => item.session?.id && item.session?.starts_at && item.session?.ends_at)
    .map((item) => {
      const id = item.session?.id as string;
      const selected = selectedIds.includes(id);
      return {
        id,
        title: `${selected ? '✓ ' : ''}${item.offering?.name ?? 'Session'}`,
        startsAt: item.session?.starts_at as string,
        endsAt: item.session?.ends_at as string,
        capacity: {
          booked: (item.session?.booked_count ?? 0) + (item.session?.held_count ?? 0),
          total: item.session?.capacity ?? item.offering?.default_capacity ?? 0,
        },
        location: item.venue?.name ?? undefined,
      };
    });

  const onConfirm = async () => {
    if (!playerId || selectedSessions.length === 0) return;
    setSubmitting(true);
    setResults(null);
    const outcome: BookingResult[] = [];
    const succeeded: string[] = [];

    // Continue through failures so one full/conflicting session does not block
    // the rest. Failures stay selected so the customer can retry them.
    for (const item of selectedSessions) {
      const sessionId = item.session?.id;
      if (!sessionId) continue;
      const label = sessionLabel(item);
      try {
        if (effectiveMethod === 'credits') {
          await createBooking.mutateAsync({
            data: { player_id: playerId, session_id: sessionId, method: 'credits' },
          });
        } else {
          const holdResult = await createBooking.mutateAsync({
            data: { player_id: playerId, session_id: sessionId, method: 'paid' },
          });
          const hold = responseData<{ id?: string }>(holdResult);
          if (!hold?.id) throw new Error('Could not hold this session');
          await addToCart.mutateAsync({
            data: { type: 'drop_in', ref_id: hold.id, quantity: 1 },
          });
        }
        outcome.push({ sessionId, label, ok: true });
        succeeded.push(sessionId);
      } catch (error) {
        outcome.push({
          sessionId,
          label,
          ok: false,
          message: friendlyError(errorCode(error), errorMessage(error)),
        });
      }
    }

    setSelectedIds((current) => current.filter((id) => !succeeded.includes(id)));
    setResults(outcome);
    setSubmitting(false);

    const okCount = outcome.filter((entry) => entry.ok).length;
    if (effectiveMethod === 'credits') {
      await queryClient.invalidateQueries({ queryKey: bookingsQueryKey() });
      await queryClient.invalidateQueries({ queryKey: creditsQueryKey() });
      toast({
        title: `${okCount} of ${outcome.length} session${outcome.length === 1 ? '' : 's'} booked`,
        variant: okCount === outcome.length ? 'success' : 'danger',
      });
    } else if (outcome.length > 0 && okCount === outcome.length) {
      toast({ title: 'Added to cart', variant: 'success' });
      navigate('/cart');
    } else {
      toast({ title: 'Some sessions could not be added to your cart', variant: 'danger' });
    }
  };

  const deferHref = hasCredits ? '/credits' : '/packages';

  return (
    <div className="flex flex-col gap-4">
      <Button asChild variant="ghost" size="sm" className="self-start">
        <Link to="/schedule">
          <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Back to schedule
        </Link>
      </Button>

      <QueryState
        loading={sessionsQuery.isLoading || offeringsQuery.isLoading || playersQuery.isLoading}
        error={sessionsQuery.isError ? errorMessage(sessionsQuery.error) : undefined}
        onRetry={() => void sessionsQuery.refetch()}
      >
        {!offering ? (
          <p className="text-sm text-muted-foreground">This offering is not available.</p>
        ) : (
          <>
            <PageHeader
              title={`Schedule ${offering.name} sessions`}
              description="Choose a player, pick the sessions that suit you, then book with sessions or as drop-ins."
            />

            <TimezoneNote timezone={timezone} />

            <Card>
              <CardContent className="flex flex-col gap-3 pt-4">
                <label className="flex flex-col gap-1 text-sm">
                  <span className="font-medium">Offering</span>
                  <Select
                    aria-label="Offering"
                    value={offeringId}
                    onValueChange={(value) => navigate(`/offerings/${value}/schedule`)}
                    options={offerings.map((option) => ({
                      value: option.id,
                      label: option.name,
                    }))}
                  />
                </label>
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
                    to schedule sessions.
                  </p>
                ) : null}
                {player && !ageOk ? (
                  <p className="text-sm text-danger">
                    {player.first_name} is outside the age range for this offering.
                  </p>
                ) : null}
              </CardContent>
            </Card>

            <div className="flex flex-wrap items-center justify-between gap-2">
              <h2 className="text-sm font-medium">Choose sessions</h2>
              <div role="group" aria-label="View" className="flex rounded-md border border-border">
                <button
                  type="button"
                  aria-pressed={view === 'list'}
                  onClick={() => setView('list')}
                  className={`flex items-center gap-1 rounded-l-md px-3 py-2 text-sm ${
                    view === 'list' ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'
                  }`}
                >
                  <List className="h-4 w-4" aria-hidden="true" /> List
                </button>
                <button
                  type="button"
                  aria-pressed={view === 'calendar'}
                  onClick={() => setView('calendar')}
                  className={`flex items-center gap-1 rounded-r-md px-3 py-2 text-sm ${
                    view === 'calendar' ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'
                  }`}
                >
                  <CalendarDays className="h-4 w-4" aria-hidden="true" /> Calendar
                </button>
              </div>
            </div>

            {selectableSessions.length === 0 ? (
              <EmptyState
                icon={<CalendarDays className="h-8 w-8" />}
                title="No upcoming sessions"
                description="There are no bookable sessions for this offering in the next 90 days."
              />
            ) : view === 'calendar' ? (
              <Calendar
                key={firstEventDate(calendarEvents)?.toISOString() ?? 'no-sessions'}
                events={calendarEvents}
                timezone={timezone}
                defaultView="week"
                anchorDate={firstEventDate(calendarEvents)}
                onEventClick={(event) => toggle(event.id)}
              />
            ) : (
              <ul className="flex flex-col gap-2">
                {selectableSessions.map((item) => {
                  const id = item.session?.id as string;
                  const checked = selectedIds.includes(id);
                  const seatsLeft = item.seats_left ?? item.session?.seats_left ?? 0;
                  return (
                    <li key={id}>
                      <label
                        className={`flex cursor-pointer items-center gap-3 rounded-md border p-3 text-sm ${
                          checked ? 'border-primary/60 bg-primary/5' : 'border-border'
                        }`}
                      >
                        <Checkbox
                          checked={checked}
                          onCheckedChange={() => toggle(id)}
                          aria-label={`Select ${sessionLabel(item)}`}
                        />
                        <span className="flex flex-col">
                          <VenueTime
                            instant={item.session?.starts_at as string}
                            timezone={item.venue?.timezone ?? timezone}
                          />
                          {item.venue?.name ? (
                            <span className="text-xs text-muted-foreground">{item.venue.name}</span>
                          ) : null}
                        </span>
                        <span className="ml-auto text-xs text-muted-foreground">
                          {seatsLeft} seats left
                        </span>
                      </label>
                    </li>
                  );
                })}
              </ul>
            )}

            <Card>
              <CardContent className="flex flex-col gap-3 pt-4">
                <div className="flex items-center justify-between gap-2">
                  <h2 className="text-sm font-medium">
                    {selectedIds.length} session{selectedIds.length === 1 ? '' : 's'} selected
                  </h2>
                  {selectedIds.length > 0 ? (
                    <Button variant="ghost" size="sm" onClick={() => setSelectedIds([])}>
                      Clear
                    </Button>
                  ) : null}
                </div>
                {selectedIds.length === 0 ? (
                  <p className="text-sm text-muted-foreground">
                    Pick one or more sessions from the list or calendar.
                  </p>
                ) : (
                  <ul className="flex flex-col divide-y divide-border">
                    {selectedSessions.map((item) => {
                      const id = item.session?.id as string;
                      return (
                        <li
                          key={id}
                          className="flex flex-wrap items-center justify-between gap-2 py-2 text-sm"
                        >
                          <VenueTime
                            instant={item.session?.starts_at as string}
                            timezone={item.venue?.timezone ?? timezone}
                          />
                          <Button
                            variant="ghost"
                            size="sm"
                            aria-label={`Remove ${sessionLabel(item)}`}
                            onClick={() => toggle(id)}
                          >
                            Remove
                          </Button>
                        </li>
                      );
                    })}
                  </ul>
                )}
              </CardContent>
            </Card>

            <Card>
              <CardContent className="flex flex-col gap-3 pt-4">
                <h2 className="text-sm font-medium">Payment method</h2>
                <RadioGroup
                  label="Payment method"
                  value={effectiveMethod}
                  onValueChange={(value) => setMethod(value as 'credits' | 'paid')}
                  options={[
                    {
                      value: 'credits',
                      label: hasCredits
                        ? `Use sessions (${eligibleCreditTotal} available)`
                        : 'Use sessions (none available)',
                      disabled: !hasCredits,
                    },
                    {
                      value: 'paid',
                      label:
                        offering.drop_in_price != null
                          ? 'Pay as a drop-in'
                          : 'Pay online at checkout',
                    },
                  ]}
                />
                {effectiveMethod === 'paid' && offering.drop_in_price != null ? (
                  <p className="text-sm text-muted-foreground">
                    Drop-in <Money amountMinor={offering.drop_in_price} /> per session
                    {selectedIds.length > 0 ? ` · ${selectedIds.length} selected` : ''}
                  </p>
                ) : null}
                {effectiveMethod === 'credits' && offering.credit_cost ? (
                  <p className="text-sm text-muted-foreground">
                    {offering.credit_cost * selectedIds.length} session
                    {offering.credit_cost * selectedIds.length === 1 ? '' : 's'} will be used.
                  </p>
                ) : null}
                {effectiveMethod === 'credits' && selectedIds.length > eligibleCreditTotal ? (
                  <p className="text-sm text-danger">
                    You selected {selectedIds.length} sessions but only {eligibleCreditTotal}{' '}
                    session
                    {eligibleCreditTotal === 1 ? ' is' : 's are'} available. Choose fewer sessions
                    or pay as a drop-in.
                  </p>
                ) : null}
                {!hasCredits ? (
                  <p className="text-xs text-muted-foreground">
                    No eligible sessions. Pay as a drop-in or{' '}
                    <Link className="text-primary hover:underline" to="/packages">
                      buy a package
                    </Link>
                    .
                  </p>
                ) : null}
              </CardContent>
            </Card>

            {results ? (
              <Card>
                <CardContent className="flex flex-col gap-2 pt-4">
                  <h2 className="text-sm font-medium">Booking results</h2>
                  <ul className="flex flex-col gap-1.5">
                    {results.map((result) => (
                      <li
                        key={result.sessionId}
                        className="flex flex-wrap items-center gap-2 text-sm"
                      >
                        {result.ok ? (
                          <CheckCircle2 className="h-4 w-4 text-green-600" aria-hidden="true" />
                        ) : (
                          <XCircle className="h-4 w-4 text-danger" aria-hidden="true" />
                        )}
                        <span>
                          {result.ok ? `Booked: ${result.label}` : `Not booked: ${result.label}`}
                        </span>
                        {!result.ok && result.message ? (
                          <span className="text-danger">{result.message}</span>
                        ) : null}
                      </li>
                    ))}
                  </ul>
                </CardContent>
              </Card>
            ) : null}

            <div className="flex flex-wrap items-center gap-2">
              <Button onClick={() => void onConfirm()} disabled={!canConfirm}>
                {submitting ? 'Booking…' : 'Confirm bookings'}
              </Button>
              <Button asChild variant="outline">
                <Link to={deferHref}>I&apos;ll choose dates later</Link>
              </Button>
            </div>
          </>
        )}
      </QueryState>
    </div>
  );
}
