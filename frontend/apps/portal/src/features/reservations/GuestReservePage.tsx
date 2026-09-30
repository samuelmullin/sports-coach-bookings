import { useEffect, useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, CalendarDays, List } from 'lucide-react';
import {
  Button,
  Calendar,
  Card,
  CardContent,
  Checkbox,
  EmptyState,
  formatMoney,
  RadioGroup,
  useToast,
} from '@scb/ui';
import type { CalendarEvent } from '@scb/ui';
import {
  offeringPackagesQueryKey,
  useOfferingPackages,
  useOfferings,
  useSessions,
  type OfferingResponse,
  type PackageResponse,
  type SessionListItem,
} from '../../api/endpoints';
import { errorCode, errorMessage, listItems } from '../shared/api-utils';
import { friendlyError } from '../shared/errors';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { Money } from '../shared/Money';
import { VenueTime, TimezoneNote } from '../shared/VenueTime';
import { usePortalSettings } from '../shared/extras';
import { firstEventDate } from '../shared/calendarAnchor';
import { addGuestLine, guestLineId } from '../cart/guest-cart';
import { useAddToCart } from '../cart/useCart';
import { useCustomerAuth } from '../../auth/customer-auth';
import { useReservation } from './ReservationProvider';
import type { ReservationOptionKind } from './reservation-store';

function isoDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

/**
 * Anonymous "book now" selection: pick sessions for one offering, choose a
 * purchasable option (single drop-in or a pack of N sessions), hold the seats
 * and continue into sign-up/sign-in. No auth is required to view or select.
 */
export function GuestReservePage() {
  const { offeringId = '' } = useParams<{ offeringId: string }>();
  const navigate = useNavigate();
  const { toast } = useToast();
  const settings = usePortalSettings();
  const { reserve } = useReservation();
  const { status } = useCustomerAuth();
  const authenticated = status === 'authenticated';
  const addToServerCart = useAddToCart();

  const [selectedIds, setSelectedIds] = useState<string[]>([]);
  const [view, setView] = useState<'list' | 'calendar'>('list');
  const [manualOption, setManualOption] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  const range = useMemo(() => {
    const from = new Date();
    const to = new Date();
    to.setDate(to.getDate() + 90);
    return { from: isoDate(from), to: isoDate(to) };
  }, []);

  const sessionsQuery = useSessions({ offering_id: offeringId, from: range.from, to: range.to });
  const offeringsQuery = useOfferings();
  const packsQuery = useOfferingPackages(offeringId, {
    query: { queryKey: offeringPackagesQueryKey(offeringId), enabled: Boolean(offeringId) },
  });

  const offerings = listItems<OfferingResponse>(offeringsQuery);
  const packs = listItems<PackageResponse>(packsQuery);
  const sessions = listItems<SessionListItem>(sessionsQuery);

  const offering = offerings.find((candidate) => candidate.id === offeringId);
  const sortedPacks = useMemo(
    () => [...packs].sort((a, b) => (a.credit_quantity ?? 0) - (b.credit_quantity ?? 0)),
    [packs],
  );

  // The option auto-follows how many sessions are selected: the cheapest
  // admin-defined option that covers the selection (drop-in vs a pack whose
  // size is at least the selected count). A manual pick overrides it until the
  // selection changes again.
  const autoOption = useMemo(() => {
    const count = selectedIds.length;
    if (count === 0) return 'single';

    const covering = sortedPacks.find((pack) => (pack.credit_quantity ?? 0) >= count);
    const dropInPrice = offering?.drop_in_price;

    if (!covering) return 'single';

    if (typeof dropInPrice !== 'number') {
      // Credits-only offering: only switch to a pack on an exact match.
      return covering.credit_quantity === count ? `pack:${covering.id}` : 'single';
    }

    return covering.price <= dropInPrice * count ? `pack:${covering.id}` : 'single';
  }, [selectedIds.length, sortedPacks, offering?.drop_in_price]);

  useEffect(() => {
    setManualOption(null);
  }, [selectedIds.length]);

  const option = manualOption ?? autoOption;
  const chosenPack = packs.find((pack) => `pack:${pack.id}` === option);
  const optionKind: ReservationOptionKind = chosenPack ? 'pack' : 'single';
  const maxSelectable = chosenPack?.credit_quantity ?? Number.POSITIVE_INFINITY;

  // When paying per session (drop-in), nudge toward the next pack if it would
  // lower the per-session price.
  const nudge = useMemo(() => {
    const count = selectedIds.length;
    if (option !== 'single' || count === 0) return null;
    if (typeof offering?.drop_in_price !== 'number') return null;

    const next =
      sortedPacks.find((pack) => (pack.credit_quantity ?? 0) > count) ??
      sortedPacks.find((pack) => (pack.credit_quantity ?? 0) >= count);
    if (!next?.credit_quantity) return null;

    const perSession = Math.round(next.price / next.credit_quantity);
    const saving = offering.drop_in_price - perSession;
    if (saving <= 0) return null;

    return { more: next.credit_quantity - count, saving, packName: next.name };
  }, [option, selectedIds.length, sortedPacks, offering?.drop_in_price]);

  useEffect(() => {
    setSelectedIds([]);
  }, [offeringId]);

  const selectableSessions = useMemo(
    () =>
      sessions.filter((item) => {
        const id = item.session?.id;
        if (!id || !item.session?.starts_at) return false;
        if (item.bookable === false) return false;
        return (item.seats_left ?? item.session?.seats_left ?? 0) > 0;
      }),
    [sessions],
  );

  const timezone = useMemo(() => {
    const zone = selectableSessions.find((item) => item.venue?.timezone)?.venue?.timezone;
    return zone ?? settings.timezone;
  }, [selectableSessions, settings.timezone]);

  const overLimit = selectedIds.length > maxSelectable;
  const canReserve = selectedIds.length > 0 && !overLimit && !submitting;

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

  const onReserve = async () => {
    if (selectedIds.length === 0) return;
    setSubmitting(true);
    try {
      const stored = await reserve({
        offeringId,
        optionKind,
        packId: chosenPack?.id,
        sessionIds: selectedIds,
      });
      if (chosenPack) await addPackToCart(chosenPack);
      toast({ title: 'Sessions held', variant: 'success' });
      if (authenticated) {
        navigate(`/reservations/${stored.id}/complete`);
      } else {
        navigate('/register', { state: { from: `/reservations/${stored.id}/complete` } });
      }
    } catch (error) {
      toast({ title: friendlyError(errorCode(error), errorMessage(error)), variant: 'danger' });
      setSubmitting(false);
    }
  };

  // Add the chosen pack to the right cart: the server cart when signed in,
  // otherwise the guest cart that merges after sign-in.
  const addPackToCart = async (pack: PackageResponse) => {
    if (authenticated) {
      await addToServerCart.mutateAsync({
        data: { type: 'package', ref_id: pack.id, quantity: 1 },
      });
      return;
    }
    addGuestLine({
      id: guestLineId('package', pack.id),
      type: 'package',
      ref_id: pack.id,
      quantity: 1,
      snapshot: {
        title: pack.name,
        subtitle: offering?.name,
        priceMinor: pack.price,
        currency: settings.currency,
      },
    });
  };

  // Defer: buy the pack now and pick the session dates whenever they're ready.
  const onChooseLater = () => {
    if (!chosenPack) {
      toast({ title: 'Choose a pack to book the dates later', variant: 'danger' });
      return;
    }
    void addPackToCart(chosenPack).then(() => {
      toast({
        title: 'Pack added — pick your session dates whenever you are ready',
        variant: 'success',
      });
      navigate('/cart');
    });
  };

  return (
    <div className="flex flex-col gap-4">
      <Button asChild variant="ghost" size="sm" className="self-start">
        <Link to={`/offerings/${offeringId}`}>
          <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Back to offering
        </Link>
      </Button>

      <QueryState
        loading={sessionsQuery.isLoading || offeringsQuery.isLoading}
        error={sessionsQuery.isError ? errorMessage(sessionsQuery.error) : undefined}
        onRetry={() => void sessionsQuery.refetch()}
      >
        {!offering ? (
          <p className="text-sm text-muted-foreground">This offering is not available.</p>
        ) : (
          <>
            <PageHeader
              title={`Reserve ${offering.name} sessions`}
              description="Pick the sessions you want, hold them for 10 minutes, then create your account to confirm."
            />

            <TimezoneNote timezone={timezone} />

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
                          aria-label={`Select ${item.offering?.name ?? 'session'}`}
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
                <h2 className="text-sm font-medium">Choose an option</h2>
                <RadioGroup
                  label="Booking option"
                  value={option}
                  onValueChange={setManualOption}
                  options={[
                    {
                      value: 'single',
                      label:
                        typeof offering.drop_in_price === 'number'
                          ? `1 Session - ${formatMoney(offering.drop_in_price, settings.currency)}`
                          : '1 Session',
                    },
                    ...sortedPacks.map((pack) => ({
                      value: `pack:${pack.id}`,
                      label: `${pack.credit_quantity} Session${
                        pack.credit_quantity === 1 ? '' : 's'
                      } - ${formatMoney(pack.price, settings.currency)}`,
                    })),
                  ]}
                />
                {chosenPack?.validity_days ? (
                  <p className="text-xs text-muted-foreground">
                    Valid {chosenPack.validity_days} days
                  </p>
                ) : null}
                {nudge ? (
                  <p className="text-sm font-medium text-primary" data-testid="pack-nudge">
                    Book {nudge.more} more session{nudge.more === 1 ? '' : 's'} and save{' '}
                    <Money amountMinor={nudge.saving} /> per session!
                  </p>
                ) : null}
                {chosenPack && selectedIds.length < chosenPack.credit_quantity ? (
                  <p className="text-sm text-muted-foreground" data-testid="schedule-summary">
                    {selectedIds.length} Session{selectedIds.length === 1 ? '' : 's'} scheduled.{' '}
                    {chosenPack.credit_quantity - selectedIds.length} Session
                    {chosenPack.credit_quantity - selectedIds.length === 1 ? '' : 's'} will be
                    available to schedule later.
                  </p>
                ) : null}
              </CardContent>
            </Card>

            <div className="flex flex-wrap items-center gap-2">
              {overLimit ? (
                <p className="text-sm text-danger">
                  You selected more sessions than this pack includes.
                </p>
              ) : null}
              <Button onClick={() => void onReserve()} disabled={!canReserve}>
                {submitting ? 'Holding…' : 'Reserve & continue'}
              </Button>
              <Button
                variant="outline"
                onClick={onChooseLater}
                disabled={!chosenPack || submitting}
              >
                Choose dates later
              </Button>
              <p className="text-xs text-muted-foreground">
                No payment yet — we hold your seats for 10 minutes while you finish booking.
                Choosing dates later buys the pack now; book each session whenever you like.
              </p>
            </div>
          </>
        )}
      </QueryState>
    </div>
  );
}
