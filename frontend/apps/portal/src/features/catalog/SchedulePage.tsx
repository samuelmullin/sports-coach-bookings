import { useMemo, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { useNavigate } from 'react-router-dom';
import { CalendarDays, List } from 'lucide-react';
import { Calendar, EmptyState, Select } from '@scb/ui';
import type { CalendarEvent } from '@scb/ui';
import {
  playersQueryKey,
  useOfferings,
  usePlayers,
  useSessions,
  useVenues,
  type OfferingResponse,
  type PlayerResponse,
  type SessionIndexParams,
  type SessionListItem,
  type VenueResponse,
} from '../../api/endpoints';
import { listItems } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { PlayerSelect } from '../shared/PlayerSelect';
import { TimezoneNote } from '../shared/VenueTime';
import { usePortalSettings } from '../shared/extras';
import { firstEventDate } from '../shared/calendarAnchor';
import { useCustomerAuth } from '../../auth/customer-auth';
import { isAgeEligible } from '../shared/age';
import { SessionCard } from './SessionCard';

function isoDate(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export function SchedulePage() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const { status } = useCustomerAuth();
  const authenticated = status === 'authenticated';
  const settings = usePortalSettings();

  const [offeringId, setOfferingId] = useState<string | undefined>();
  const [venueId, setVenueId] = useState<string | undefined>();
  const [format, setFormat] = useState<string | undefined>();
  const [playerId, setPlayerId] = useState<string | undefined>();
  const [view, setView] = useState<'list' | 'calendar'>('list');

  const range = useMemo(() => {
    const from = new Date();
    const to = new Date();
    to.setDate(to.getDate() + 90);
    return { from: isoDate(from), to: isoDate(to) };
  }, []);

  const params: SessionIndexParams = {
    from: range.from,
    to: range.to,
    offering_id: offeringId,
    venue_id: venueId,
    format,
    player_id: playerId,
  };

  const sessionsQuery = useSessions(params);
  const offeringsQuery = useOfferings();
  const venuesQuery = useVenues();
  const playersQuery = usePlayers({
    query: { queryKey: playersQueryKey(), enabled: authenticated, retry: false },
  });

  const sessions = listItems<SessionListItem>(sessionsQuery);
  const offerings = listItems<OfferingResponse>(offeringsQuery);
  const venues = listItems<VenueResponse>(venuesQuery);
  const players = listItems<PlayerResponse>(playersQuery);
  const selectedPlayer = players.find((player) => player.id === playerId);

  const offeringById = useMemo(
    () => new Map(offerings.map((offering) => [offering.id, offering])),
    [offerings],
  );

  const visibleSessions = useMemo(() => {
    if (!selectedPlayer) return sessions;
    return sessions.filter((item) =>
      isAgeEligible(selectedPlayer, item.offering?.min_age, item.offering?.max_age),
    );
  }, [sessions, selectedPlayer]);

  const timezone = useMemo(() => {
    const venueZones = venues.map((venue) => venue.timezone).filter(Boolean);
    if (venueId) {
      const venue = venues.find((candidate) => candidate.id === venueId);
      if (venue?.timezone) return venue.timezone;
    }
    return venueZones[0] ?? settings.timezone;
  }, [venues, venueId, settings.timezone]);

  const calendarEvents: CalendarEvent[] = visibleSessions
    .filter((item) => item.session?.starts_at && item.session?.ends_at)
    .map((item) => ({
      id: item.session?.id ?? '',
      title: item.offering?.name ?? 'Session',
      startsAt: item.session?.starts_at as string,
      endsAt: item.session?.ends_at as string,
      capacity: {
        booked: (item.session?.booked_count ?? 0) + (item.session?.held_count ?? 0),
        total: item.session?.capacity ?? item.offering?.default_capacity ?? 0,
      },
      location: item.venue?.name ?? undefined,
    }));

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title={t('nav.schedule')}
        description={t('schedule.subtitle')}
        actions={
          <div role="group" aria-label="View" className="flex rounded-md border border-border">
            <button
              type="button"
              aria-pressed={view === 'list'}
              onClick={() => setView('list')}
              className={`flex items-center gap-1 rounded-l-md px-3 py-2 text-sm ${view === 'list' ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'}`}
            >
              <List className="h-4 w-4" aria-hidden="true" /> List
            </button>
            <button
              type="button"
              aria-pressed={view === 'calendar'}
              onClick={() => setView('calendar')}
              className={`flex items-center gap-1 rounded-r-md px-3 py-2 text-sm ${view === 'calendar' ? 'bg-primary text-primary-foreground' : 'hover:bg-muted'}`}
            >
              <CalendarDays className="h-4 w-4" aria-hidden="true" /> Calendar
            </button>
          </div>
        }
      />

      <div className="grid grid-cols-1 gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Offering</span>
          <Select
            aria-label="Offering"
            placeholder="All offerings"
            value={offeringId}
            onValueChange={(value) => setOfferingId(value === '__all__' ? undefined : value)}
            options={[
              { value: '__all__', label: 'All offerings' },
              ...offerings.map((offering) => ({ value: offering.id, label: offering.name })),
            ]}
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Venue</span>
          <Select
            aria-label="Venue"
            placeholder="All venues"
            value={venueId}
            onValueChange={(value) => setVenueId(value === '__all__' ? undefined : value)}
            options={[
              { value: '__all__', label: 'All venues' },
              ...venues.map((venue) => ({ value: venue.id, label: venue.name })),
            ]}
          />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="font-medium">Format</span>
          <Select
            aria-label="Format"
            placeholder="Any format"
            value={format}
            onValueChange={(value) => setFormat(value === '__all__' ? undefined : value)}
            options={[
              { value: '__all__', label: 'Any format' },
              { value: 'private', label: 'Private' },
              { value: 'semi_private', label: 'Semi-private' },
              { value: 'group', label: 'Group' },
            ]}
          />
        </label>
        {authenticated ? (
          <label className="flex flex-col gap-1 text-sm">
            <span className="font-medium">Player</span>
            <PlayerSelect players={players} value={playerId} onChange={setPlayerId} />
          </label>
        ) : null}
      </div>

      <TimezoneNote timezone={timezone} />

      <QueryState
        loading={sessionsQuery.isLoading || offeringsQuery.isLoading}
        error={sessionsQuery.isError ? 'We could not load the schedule.' : undefined}
        onRetry={() => void sessionsQuery.refetch()}
      >
        {view === 'calendar' ? (
          <Calendar
            key={firstEventDate(calendarEvents)?.toISOString() ?? 'no-sessions'}
            events={calendarEvents}
            timezone={timezone}
            defaultView="week"
            anchorDate={firstEventDate(calendarEvents)}
            onEventClick={(event) => navigate(`/sessions/${event.id}`)}
          />
        ) : visibleSessions.length === 0 ? (
          <EmptyState
            icon={<CalendarDays className="h-8 w-8" />}
            title={t('empty.schedule')}
            description="Try a different filter or check back soon."
          />
        ) : (
          <ul className="flex flex-col gap-3">
            {visibleSessions.map((item, index) => {
              const offering = offeringById.get(item.offering?.id ?? '');
              return (
                <li key={item.session?.id ?? `session-${index}`}>
                  <SessionCard
                    item={item}
                    timezone={timezone}
                    canBook={authenticated}
                    creditCost={offering?.credit_cost}
                    dropInPrice={offering?.drop_in_price ?? undefined}
                  />
                </li>
              );
            })}
          </ul>
        )}
      </QueryState>
    </div>
  );
}
