import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { AlertTriangle, CheckCircle2 } from 'lucide-react';
import { useQueryClient } from '@tanstack/react-query';
import { Button, Card, CardContent, RadioGroup, useToast } from '@scb/ui';
import {
  bookingsQueryKey,
  creditsQueryKey,
  useCredits,
  usePlayers,
  type CreditBalance,
  type PlayerResponse,
} from '../../api/endpoints';
import { useAddToCart } from '../cart/useCart';
import { errorCode, errorMessage, listItems } from '../shared/api-utils';
import { friendlyError } from '../shared/errors';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { PlayerSelect } from '../shared/PlayerSelect';
import { VenueTime, TimezoneNote } from '../shared/VenueTime';
import { usePortalSettings } from '../shared/extras';
import { useReservation } from './ReservationProvider';

/**
 * Authenticated completion of a guest reservation: assign a player per held
 * session, choose the payment method and convert.
 *
 * Ordering:
 * - `paid` (single drop-ins): convert to held bookings, add each as a
 *   `drop_in` cart line, then send the customer to the cart.
 * - `credits` (pack): if the pack has been paid the credits exist and we
 *   convert immediately; otherwise the customer buys the pack first and the
 *   post-payment page converts using the assignments saved here.
 */
export function ReservationCompletePage() {
  const { id = '' } = useParams<{ id: string }>();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const settings = usePortalSettings();
  const addToCart = useAddToCart();

  const { reservation, status, convert, touch, setAssignments, markExpired } = useReservation();
  const playersQuery = usePlayers();
  const creditsQuery = useCredits();

  const players = listItems<PlayerResponse>(playersQuery);
  const credits = listItems<CreditBalance>(creditsQuery);

  const [method, setMethod] = useState<'credits' | 'paid'>('paid');
  const [assignments, setAssignmentsState] = useState<Record<string, string>>({});
  const [submitting, setSubmitting] = useState(false);

  const offeringId = reservation?.offeringId;
  const selectAgainHref = offeringId ? `/offerings/${offeringId}/schedule` : '/schedule';

  const eligibleCreditTotal = useMemo(
    () =>
      credits
        .filter((entry) => entry.amount > 0)
        .filter((entry) => entry.offering_id === offeringId || entry.offering_id === 'any')
        .reduce((sum, entry) => sum + entry.amount, 0),
    [credits, offeringId],
  );
  const sessionsNeeded = reservation?.sessionIds.length ?? 0;
  const hasEnoughCredits = eligibleCreditTotal >= sessionsNeeded;

  useEffect(() => {
    if (reservation?.optionKind === 'pack') setMethod('credits');
    else if (eligibleCreditTotal > 0) setMethod('credits');
  }, [reservation?.optionKind, eligibleCreditTotal]);

  useEffect(() => {
    const firstPlayer = players[0]?.id;
    if (!reservation || !firstPlayer) return;
    setAssignmentsState((current) => {
      const next = { ...current };
      for (const sessionId of reservation.sessionIds) {
        if (!next[sessionId]) next[sessionId] = firstPlayer;
      }
      return next;
    });
  }, [reservation, players]);

  const assignmentList = useMemo(
    () =>
      (reservation?.sessionIds ?? []).map((sessionId) => ({
        session_id: sessionId,
        player_id: assignments[sessionId] ?? players[0]?.id ?? '',
        method,
      })),
    [reservation?.sessionIds, assignments, players, method],
  );

  const saveAssignments = () => {
    setAssignments(assignmentList.filter((assignment) => assignment.player_id));
  };

  const onConfirm = async () => {
    if (!reservation) return;
    if (assignmentList.some((assignment) => !assignment.player_id)) {
      toast({ title: 'Choose a player for every session', variant: 'danger' });
      return;
    }
    setSubmitting(true);
    try {
      await touch({ force: true });
      const bookings = await convert(assignmentList);
      if (method === 'paid') {
        for (const booking of bookings) {
          await addToCart.mutateAsync({
            data: { type: 'drop_in', ref_id: booking.id, quantity: 1 },
          });
        }
        toast({ title: 'Sessions held in your cart', variant: 'success' });
        navigate('/cart');
      } else {
        await queryClient.invalidateQueries({ queryKey: bookingsQueryKey() });
        await queryClient.invalidateQueries({ queryKey: creditsQueryKey() });
        toast({ title: 'Booking confirmed', variant: 'success' });
        navigate('/bookings');
      }
    } catch (error) {
      const code = errorCode(error);
      if (code === 'reservation_expired' || code === 'not_found') {
        markExpired();
        toast({ title: friendlyError(code, errorMessage(error)), variant: 'danger' });
      } else {
        toast({ title: friendlyError(code, errorMessage(error)), variant: 'danger' });
      }
      setSubmitting(false);
    }
  };

  const abandon = (
    <Card className="border-danger/40 bg-danger/5">
      <CardContent className="flex flex-col items-start gap-3 pt-6">
        <AlertTriangle className="h-8 w-8 text-danger" aria-hidden="true" />
        <h2 className="text-lg font-semibold">Your held sessions were released</h2>
        <p className="text-sm text-muted-foreground" data-testid="reservation-abandon-message">
          Your reserved session times were released due to inactivity. Select sessions again to
          continue.
        </p>
        <div className="flex flex-wrap gap-2">
          <Button asChild>
            <Link to={selectAgainHref}>Select sessions again</Link>
          </Button>
          <Button asChild variant="outline">
            <Link to="/schedule">Browse schedule</Link>
          </Button>
        </div>
      </CardContent>
    </Card>
  );

  if (!reservation || reservation.id !== id || status === 'expired') {
    return (
      <div className="flex flex-col gap-4">
        <PageHeader title="Confirm your booking" />
        {abandon}
      </div>
    );
  }

  const showPackDeferral =
    reservation.optionKind === 'pack' && method === 'credits' && !hasEnoughCredits;

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Confirm your booking"
        description="Your sessions are held. Assign a player, then confirm."
      />
      <TimezoneNote timezone={settings.timezone} />

      <QueryState
        loading={playersQuery.isLoading}
        error={playersQuery.isError ? errorMessage(playersQuery.error) : undefined}
        onRetry={() => void playersQuery.refetch()}
      >
        <Card>
          <CardContent className="flex flex-col gap-3 pt-4">
            <h2 className="text-sm font-medium">Held sessions</h2>
            <ul className="flex flex-col divide-y divide-border">
              {reservation.sessionIds.map((sessionId) => {
                const summary = reservation.sessions.find(
                  (session) => session.session_id === sessionId,
                );
                return (
                  <li
                    key={sessionId}
                    className="flex flex-wrap items-center justify-between gap-3 py-3 text-sm"
                  >
                    {summary?.starts_at ? (
                      <VenueTime instant={summary.starts_at} timezone={settings.timezone} />
                    ) : (
                      <span>Session</span>
                    )}
                    {players.length > 0 ? (
                      <div className="w-48">
                        <PlayerSelect
                          players={players}
                          value={assignments[sessionId]}
                          onChange={(playerId) =>
                            setAssignmentsState((current) => ({
                              ...current,
                              [sessionId]: playerId ?? '',
                            }))
                          }
                        />
                      </div>
                    ) : null}
                  </li>
                );
              })}
            </ul>

            {players.length === 0 ? (
              <p className="text-sm text-muted-foreground">
                <Link className="text-primary hover:underline" to="/players">
                  Add a player
                </Link>{' '}
                before confirming these sessions.
              </p>
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
                  label: eligibleCreditTotal
                    ? `Use sessions (${eligibleCreditTotal} available)`
                    : 'Use sessions (none available)',
                  disabled: eligibleCreditTotal === 0,
                },
                { value: 'paid', label: 'Pay as a drop-in' },
              ]}
            />
            {showPackDeferral ? (
              <p className="text-sm text-muted-foreground">
                You need {sessionsNeeded} session{sessionsNeeded === 1 ? '' : 's'} for these dates.
                Buy your pack to confirm them — you can change this later.
              </p>
            ) : null}
          </CardContent>
        </Card>

        <div className="flex flex-wrap items-center gap-2">
          {showPackDeferral ? (
            <Button
              onClick={() => {
                saveAssignments();
                navigate('/cart');
              }}
            >
              Buy pack & confirm
            </Button>
          ) : (
            <Button onClick={() => void onConfirm()} disabled={submitting || players.length === 0}>
              {submitting ? 'Confirming…' : 'Confirm booking'}
            </Button>
          )}
          <Button asChild variant="outline">
            <Link to={selectAgainHref}>
              <CheckCircle2 className="h-4 w-4" aria-hidden="true" /> Choose different sessions
            </Link>
          </Button>
        </div>
      </QueryState>
    </div>
  );
}
