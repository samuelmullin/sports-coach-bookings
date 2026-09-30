import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { CalendarDays, List, MapPin, Navigation } from 'lucide-react';
import {
  Badge,
  Button,
  Calendar,
  Card,
  CardContent,
  EmptyState,
  TabsView,
  dateKeyInZone,
  formatInZone,
} from '@scb/ui';
import { useCoachSessions } from '../../api/endpoints';
import { errorMessage } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';
import { useTenantSettings } from '../shared/useTenantSettings';
import { coachSessionItems, directionsUrl, sessionTime, sessionTitle } from './coach-utils';
import type { CoachSessionEntry } from './types';

function startOfWindow(daysAgo: number): Date {
  const date = new Date();
  date.setHours(0, 0, 0, 0);
  date.setDate(date.getDate() - daysAgo);
  return date;
}

function endOfWindow(daysAhead: number): Date {
  const date = new Date();
  date.setHours(23, 59, 59, 999);
  date.setDate(date.getDate() + daysAhead);
  return date;
}

function groupByDay(
  entries: CoachSessionEntry[],
  timezone: string,
): { key: string; label: string; entries: CoachSessionEntry[] }[] {
  const groups = new Map<string, CoachSessionEntry[]>();
  for (const entry of entries) {
    const startsAt = entry.session?.starts_at;
    if (!startsAt) continue;
    const key = dateKeyInZone(startsAt, timezone);
    const list = groups.get(key) ?? [];
    list.push(entry);
    groups.set(key, list);
  }
  return [...groups.entries()]
    .sort(([a], [b]) => (a < b ? -1 : 1))
    .map(([key, dayEntries]) => ({
      key,
      label: formatInZone(`${key}T12:00:00Z`, timezone, 'EEEE, MMMM d'),
      entries: dayEntries.sort(
        (a, b) =>
          new Date(a.session?.starts_at ?? 0).getTime() -
          new Date(b.session?.starts_at ?? 0).getTime(),
      ),
    }));
}

function isUpcoming(entry: CoachSessionEntry, timezone: string): boolean {
  const startsAt = entry.session?.starts_at;
  if (!startsAt) return false;
  return dateKeyInZone(startsAt, timezone) >= dateKeyInZone(new Date(), timezone);
}

export function MySessionsPage() {
  const { timezone } = useTenantSettings();
  const [tab, setTab] = useState<'upcoming' | 'past'>('upcoming');
  const [layout, setLayout] = useState<'agenda' | 'calendar'>('agenda');

  const query = useCoachSessions({
    from: startOfWindow(60).toISOString(),
    to: endOfWindow(90).toISOString(),
  });
  const entries = coachSessionItems(query);

  const shown = useMemo(
    () =>
      entries
        .filter((entry) => isUpcoming(entry, timezone) === (tab === 'upcoming'))
        .sort(
          (a, b) =>
            new Date(a.session?.starts_at ?? 0).getTime() -
            new Date(b.session?.starts_at ?? 0).getTime(),
        ),
    [entries, tab, timezone],
  );

  const groups = useMemo(() => groupByDay(shown, timezone), [shown, timezone]);

  const events = entries
    .filter((entry) => entry.session?.starts_at)
    .map((entry) => ({
      id: entry.session?.id ?? '',
      title: sessionTitle(entry),
      startsAt: entry.session?.starts_at as string,
      endsAt: entry.session?.ends_at ?? (entry.session?.starts_at as string),
      capacity: {
        booked: entry.session?.booked_count ?? 0,
        total: entry.session?.capacity ?? 0,
      },
      location: entry.venue?.name,
    }));

  const renderEntry = (entry: CoachSessionEntry) => {
    const id = entry.session?.id ?? '';
    const booked = entry.session?.booked_count ?? 0;
    const capacity = entry.session?.capacity ?? 0;
    return (
      <Card key={id} className="overflow-hidden">
        <CardContent className="flex flex-col gap-3 pt-4">
          <div className="flex items-start justify-between gap-3">
            <div className="flex flex-col gap-1">
              <Link
                to={`/my-sessions/${id}`}
                className="text-base font-semibold text-foreground hover:underline"
              >
                {sessionTitle(entry)}
              </Link>
              <p className="text-sm text-muted-foreground">{sessionTime(entry, timezone)}</p>
            </div>
            <Badge variant={booked >= capacity && capacity > 0 ? 'danger' : 'secondary'}>
              {booked}/{capacity}
            </Badge>
          </div>
          <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
            <span className="inline-flex items-center gap-1">
              <MapPin className="h-4 w-4" aria-hidden="true" />
              {entry.venue?.name ?? 'Venue TBC'}
            </span>
            <a
              className="inline-flex items-center gap-1 text-primary hover:underline"
              href={directionsUrl(entry.venue?.name, sessionTitle(entry))}
              target="_blank"
              rel="noreferrer"
            >
              <Navigation className="h-4 w-4" aria-hidden="true" />
              Directions
            </a>
          </div>
          <Button asChild size="sm" className="w-full sm:w-auto">
            <Link to={`/my-sessions/${id}`}>Open roster</Link>
          </Button>
        </CardContent>
      </Card>
    );
  };

  return (
    <div className="flex flex-col gap-4">
      <PageHeader title="My sessions" description="Your assigned coaching sessions." />

      <div className="flex flex-wrap items-center justify-between gap-2">
        <TabsView
          aria-label="Session period"
          value={tab}
          onValueChange={(value) => setTab(value as typeof tab)}
          items={[
            { value: 'upcoming', label: 'Upcoming', content: null },
            { value: 'past', label: 'Past', content: null },
          ]}
        />
        <div className="flex gap-1" role="tablist" aria-label="Layout">
          <Button
            variant={layout === 'agenda' ? 'secondary' : 'ghost'}
            size="sm"
            role="tab"
            aria-selected={layout === 'agenda'}
            onClick={() => setLayout('agenda')}
          >
            <List className="h-4 w-4" aria-hidden="true" />
            Agenda
          </Button>
          <Button
            variant={layout === 'calendar' ? 'secondary' : 'ghost'}
            size="sm"
            role="tab"
            aria-selected={layout === 'calendar'}
            onClick={() => setLayout('calendar')}
          >
            <CalendarDays className="h-4 w-4" aria-hidden="true" />
            Calendar
          </Button>
        </div>
      </div>

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {layout === 'calendar' ? (
          <Calendar events={events} timezone={timezone} defaultView="week" />
        ) : groups.length === 0 ? (
          <EmptyState
            title={tab === 'upcoming' ? 'No upcoming sessions' : 'No past sessions'}
            description="Sessions assigned to you will appear here."
          />
        ) : (
          <div className="flex flex-col gap-5">
            {groups.map((group) => (
              <section key={group.key} className="flex flex-col gap-2">
                <h2 className="text-sm font-semibold text-muted-foreground">{group.label}</h2>
                <div className="grid gap-3 sm:grid-cols-2">{group.entries.map(renderEntry)}</div>
              </section>
            ))}
          </div>
        )}
      </QueryState>
    </div>
  );
}
