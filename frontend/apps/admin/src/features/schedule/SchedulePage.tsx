import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import {
  addMonths,
  startOfMonth,
  formatDateTime,
  Badge,
  Button,
  Calendar,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  EmptyState,
  Select,
  Table,
} from '@scb/ui';
import {
  useOfferings,
  useSessions,
  useTeam,
  useVenues,
  type SessionSummary,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';
import { useTenantSettings } from '../shared/useTenantSettings';
import { SessionFormDrawer } from './SessionFormDrawer';
import { Plus } from 'lucide-react';

const PALETTE = ['#15803d', '#2563eb', '#b45309', '#be185d', '#7c3aed', '#0891b2'];

export function SchedulePage() {
  const { timezone } = useTenantSettings();
  const navigate = useNavigate();
  const monthStart = startOfMonth(new Date());
  const monthEnd = addMonths(monthStart, 1);
  const [venueFilter, setVenueFilter] = useState('');
  const [offeringFilter, setOfferingFilter] = useState('');
  const [coachFilter, setCoachFilter] = useState('');
  const [drawerOpen, setDrawerOpen] = useState(false);

  const venues = listItems<{ id: string; name: string }>(useVenues());
  const offerings = listItems<{ id: string; name: string }>(useOfferings());
  const team = listItems<{
    id?: string;
    display_name?: string | null;
    staff_user?: { email?: string };
  }>(useTeam());

  const params: Record<string, string> = {
    from: monthStart.toISOString(),
    to: monthEnd.toISOString(),
  };
  if (venueFilter) params.venue_id = venueFilter;
  if (offeringFilter) params.offering_id = offeringFilter;
  if (coachFilter) params.coach_id = coachFilter;

  const query = useSessions(params);
  const sessions = listItems<SessionSummary>(query);

  const offeringColor = (offeringId?: string) => {
    const index = offerings.findIndex((offering) => offering.id === offeringId);
    return PALETTE[(index >= 0 ? index : 0) % PALETTE.length];
  };

  const events = sessions
    .map((item) => item.session)
    .filter((session): session is NonNullable<typeof session> =>
      Boolean(session?.id && session.starts_at),
    )
    .map((session) => ({
      id: session.id as string,
      title:
        session.title_override ??
        offerings.find((o) => o.id === session.offering_id)?.name ??
        'Session',
      startsAt: session.starts_at as string,
      endsAt: session.ends_at ?? (session.starts_at as string),
      capacity: { booked: session.booked_count ?? 0, total: session.capacity ?? 0 },
      location: venues.find((venue) => venue.id === session.venue_id)?.name,
      color: offeringColor(session.offering_id),
    }));

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Schedule"
        description="All sessions across your venues."
        actions={
          <Button onClick={() => setDrawerOpen(true)}>
            <Plus className="h-4 w-4" aria-hidden="true" />
            New session
          </Button>
        }
      />

      <Card>
        <CardContent className="grid gap-3 pt-4 sm:grid-cols-3">
          <Select
            aria-label="Filter by venue"
            placeholder="All venues"
            value={venueFilter}
            onValueChange={setVenueFilter}
            options={[
              { value: '', label: 'All venues' },
              ...venues.map((v) => ({ value: v.id, label: v.name })),
            ]}
          />
          <Select
            aria-label="Filter by offering"
            placeholder="All offerings"
            value={offeringFilter}
            onValueChange={setOfferingFilter}
            options={[
              { value: '', label: 'All offerings' },
              ...offerings.map((o) => ({ value: o.id, label: o.name })),
            ]}
          />
          <Select
            aria-label="Filter by coach"
            placeholder="All coaches"
            value={coachFilter}
            onValueChange={setCoachFilter}
            options={[
              { value: '', label: 'All coaches' },
              ...team
                .filter((member) => member.id)
                .map((member) => ({
                  value: member.id as string,
                  label: member.display_name || member.staff_user?.email || 'Coach',
                })),
            ]}
          />
        </CardContent>
      </Card>

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        <Calendar
          events={events}
          timezone={timezone}
          defaultView="week"
          onEventClick={(event) => navigate(`/schedule/${event.id}`)}
        />
        {events.length === 0 ? (
          <EmptyState
            title="No sessions this month"
            description="Create a session or series to fill your calendar."
            action={<Button onClick={() => setDrawerOpen(true)}>New session</Button>}
          />
        ) : (
          <Card>
            <CardHeader>
              <CardTitle>Upcoming sessions</CardTitle>
            </CardHeader>
            <CardContent>
              <Table
                caption="Sessions"
                rowKey={(row) => row.session?.id ?? ''}
                columns={[
                  {
                    key: 'title',
                    header: 'Session',
                    cell: (row) => (
                      <Link
                        className="font-medium text-primary hover:underline"
                        to={`/schedule/${row.session?.id}`}
                      >
                        {row.session?.title_override ?? row.offering?.name ?? 'Session'}
                      </Link>
                    ),
                  },
                  {
                    key: 'when',
                    header: 'When',
                    cell: (row) =>
                      row.session?.starts_at
                        ? formatDateTime(row.session.starts_at, timezone)
                        : '—',
                  },
                  { key: 'venue', header: 'Venue', cell: (row) => row.venue?.name ?? '—' },
                  {
                    key: 'seats',
                    header: 'Seats',
                    cell: (row) => {
                      const booked = row.session?.booked_count ?? 0;
                      const capacity = row.session?.capacity ?? 0;
                      const variant = capacity > 0 && booked >= capacity ? 'danger' : 'success';
                      return (
                        <Badge variant={variant}>
                          {booked}/{capacity}
                        </Badge>
                      );
                    },
                  },
                  {
                    key: 'offering',
                    header: 'Offering',
                    cell: (row) => (
                      <span className="flex items-center gap-2">
                        <span
                          className="h-2.5 w-2.5 rounded-full"
                          style={{ background: offeringColor(row.session?.offering_id) }}
                          aria-hidden="true"
                        />
                        {row.offering?.name ?? '—'}
                      </span>
                    ),
                  },
                  {
                    key: 'warnings',
                    header: 'Conflicts',
                    cell: (row) =>
                      row.warnings && row.warnings.length > 0 ? (
                        <Badge variant="warning">{row.warnings.length}</Badge>
                      ) : (
                        '—'
                      ),
                  },
                ]}
                data={sessions}
              />
            </CardContent>
          </Card>
        )}
      </QueryState>

      <SessionFormDrawer
        open={drawerOpen}
        onOpenChange={setDrawerOpen}
        onCreated={() => void query.refetch()}
      />
    </div>
  );
}
