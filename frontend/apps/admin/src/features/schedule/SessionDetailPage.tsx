import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  EmptyState,
  FormField,
  Input,
  Modal,
  Select,
  Switch,
  Table,
  formatDateTime,
  TimePicker,
  zonedDateToUtc,
  useToast,
} from '@scb/ui';
import {
  useBookingsRoster,
  useCancelBooking,
  useCancelSession,
  useEditSessionSeries,
  useRescheduleSession,
  useSession,
  useUpdateAttendance,
  useUpdateSession,
  useVenues,
  type RosterEntry,
} from '../../api/endpoints';
import { body, errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';
import { useTenantSettings } from '../shared/useTenantSettings';
import { BookOnBehalfDialog } from './BookOnBehalfDialog';

const CANCEL_OUTCOMES = [
  { value: 'auto', label: 'Use policy outcome' },
  { value: 'full_return', label: 'Full return / refund' },
  { value: 'credit_return', label: 'Return sessions' },
  { value: 'forfeit', label: 'Forfeit' },
  { value: 'provider_cancelled', label: 'Provider cancelled' },
  { value: 'partial_refund', label: 'Partial refund' },
];

interface SessionShape {
  id: string;
  starts_at?: string | null;
  ends_at?: string | null;
  capacity?: number;
  booked_count?: number;
  seats_left?: number;
  status?: string;
  visibility?: string;
  title_override?: string | null;
  notes_public?: string | null;
  show_coaches?: boolean;
  series_id?: string | null;
  venue_id?: string;
  offering_id?: string;
}

export function SessionDetailPage() {
  const { sessionId = '' } = useParams();
  const navigate = useNavigate();
  const { timezone } = useTenantSettings();
  const { toast } = useToast();

  const detailQuery = useSession(sessionId);
  const rosterQuery = useBookingsRoster(sessionId);
  const venues = listItems<{ id: string; name: string; timezone: string }>(useVenues());
  const updateAttendance = useUpdateAttendance();
  const cancelBooking = useCancelBooking();
  const cancelSession = useCancelSession();
  const reschedule = useRescheduleSession();
  const updateSession = useUpdateSession();
  const editSeries = useEditSessionSeries();

  const detail = body<{
    session?: SessionShape;
    offering?: { name?: string };
    venue?: { name?: string };
    bookable?: boolean;
    seats_left?: number;
    warnings?: { message?: string }[];
  }>(detailQuery);
  const session = detail?.session;
  const roster = listItems<RosterEntry>(rosterQuery);

  const [bookOpen, setBookOpen] = useState(false);
  const [cancelSessionOpen, setCancelSessionOpen] = useState(false);
  const [cancelReason, setCancelReason] = useState('');
  const [pendingBooking, setPendingBooking] = useState<RosterEntry | null>(null);
  const [outcome, setOutcome] = useState('auto');
  const [refundPct, setRefundPct] = useState(0);
  const [bookingReason, setBookingReason] = useState('');
  const [rescheduleOpen, setRescheduleOpen] = useState(false);
  const [rescheduleDate, setRescheduleDate] = useState('');
  const [rescheduleTime, setRescheduleTime] = useState('18:00');
  const [editOpen, setEditOpen] = useState(false);
  const [editScope, setEditScope] = useState<'single' | 'following' | 'all'>('single');
  const [editVisibility, setEditVisibility] = useState<'public' | 'hidden'>('public');
  const [editCapacity, setEditCapacity] = useState(1);
  const [editShowCoaches, setEditShowCoaches] = useState(true);

  const isSeries = Boolean(session?.series_id);

  useEffect(() => {
    if (!session) return;
    setEditCapacity(session.capacity ?? 1);
    setEditVisibility(session.visibility === 'hidden' ? 'hidden' : 'public');
    setEditShowCoaches(session.show_coaches ?? true);
  }, [session?.id, session?.capacity, session?.visibility, session?.show_coaches]);

  const setAttendance = async (entry: RosterEntry, status: 'attended' | 'no_show') => {
    try {
      await updateAttendance.mutateAsync({ id: entry.booking_id, data: { status } });
      toast({ title: 'Attendance saved', variant: 'success' });
      void rosterQuery.refetch();
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  const confirmCancelBooking = async () => {
    if (!pendingBooking) return;
    try {
      await cancelBooking.mutateAsync({
        id: pendingBooking.booking_id,
        data: {
          outcome: outcome === 'auto' ? null : (outcome as never),
          refund_pct: outcome === 'partial_refund' ? refundPct : null,
          reason: bookingReason || null,
        },
      });
      toast({ title: 'Booking cancelled', variant: 'success' });
      void rosterQuery.refetch();
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    } finally {
      setPendingBooking(null);
    }
  };

  const confirmCancelSession = async () => {
    try {
      const result = await cancelSession.mutateAsync({
        id: sessionId,
        data: { reason: cancelReason || null },
      });
      const impact = (
        result as { data?: { impact?: { booked_count?: number; held_count?: number } } }
      ).data?.impact;
      toast({
        title: `Session cancelled (${impact?.booked_count ?? 0} bookings affected)`,
        variant: 'success',
      });
      void detailQuery.refetch();
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    } finally {
      setCancelSessionOpen(false);
    }
  };

  const submitReschedule = async () => {
    const zone = venues.find((venue) => venue.id === session?.venue_id)?.timezone ?? timezone;
    // Build the instant from local wall-clock fields in the venue timezone.
    const startsAt = zonedDateToUtc(
      new Date(`${rescheduleDate}T${rescheduleTime}:00`),
      zone,
    ).toISOString();
    try {
      await reschedule.mutateAsync({ id: sessionId, data: { starts_at: startsAt, ends_at: null } });
      toast({ title: 'Session rescheduled', variant: 'success' });
      setRescheduleOpen(false);
      void detailQuery.refetch();
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  const submitEdit = async () => {
    try {
      if (isSeries) {
        await editSeries.mutateAsync({
          id: sessionId,
          data: {
            scope: editScope,
            capacity: editCapacity,
            visibility: editVisibility,
            show_coaches: editShowCoaches,
            confirm: true,
          },
        });
      } else {
        await updateSession.mutateAsync({
          id: sessionId,
          data: {
            offering_id: session?.offering_id ?? '',
            starts_at: session?.starts_at ?? null,
            venue_id: session?.venue_id ?? '',
            capacity: editCapacity,
            visibility: editVisibility,
            show_coaches: editShowCoaches,
          },
        });
      }
      toast({ title: 'Session updated', variant: 'success' });
      setEditOpen(false);
      void detailQuery.refetch();
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title={session?.title_override ?? detail?.offering?.name ?? 'Session'}
        description={
          session?.starts_at
            ? `${formatDateTime(session.starts_at, timezone)} · ${detail?.venue?.name ?? ''}`
            : undefined
        }
        actions={
          <div className="flex flex-wrap gap-2">
            <Button variant="outline" size="sm" onClick={() => navigate('/schedule')}>
              Back
            </Button>
            <Button variant="outline" size="sm" onClick={() => setEditOpen(true)}>
              Edit
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => {
                setRescheduleDate(
                  session?.starts_at
                    ? (session.starts_at as string).slice(0, 10)
                    : new Date().toISOString().slice(0, 10),
                );
                setRescheduleOpen(true);
              }}
            >
              Reschedule
            </Button>
            <Button variant="danger" size="sm" onClick={() => setCancelSessionOpen(true)}>
              Cancel session
            </Button>
          </div>
        }
      />

      <QueryState
        loading={detailQuery.isLoading}
        error={detailQuery.isError ? errorMessage(detailQuery.error) : undefined}
        onRetry={() => void detailQuery.refetch()}
      >
        <div className="flex flex-wrap items-center gap-3">
          <Badge variant={session?.status === 'cancelled' ? 'danger' : 'success'}>
            {session?.status ?? 'scheduled'}
          </Badge>
          <Badge variant="secondary">
            {session?.booked_count ?? 0}/{session?.capacity ?? 0} seats
          </Badge>
          <Badge variant={session?.visibility === 'public' ? 'success' : 'outline'}>
            {session?.visibility ?? 'public'}
          </Badge>
          {detail?.warnings?.length ? (
            <Badge variant="warning">{detail.warnings.length} conflicts</Badge>
          ) : null}
        </div>

        <Card>
          <CardHeader className="flex-row items-center justify-between">
            <CardTitle>Roster</CardTitle>
            <Button
              size="sm"
              onClick={() => setBookOpen(true)}
              disabled={session?.status === 'cancelled'}
            >
              Book on behalf
            </Button>
          </CardHeader>
          <CardContent>
            {roster.length === 0 ? (
              <EmptyState
                title="No bookings yet"
                description="Book a player on behalf to fill this session."
              />
            ) : (
              <Table
                caption="Session roster"
                rowKey={(row) => row.booking_id}
                columns={[
                  {
                    key: 'player',
                    header: 'Player',
                    cell: (row) => row.player_name ?? row.player_id,
                  },
                  { key: 'method', header: 'Method', cell: (row) => row.payment_method ?? '—' },
                  { key: 'credits', header: 'Sessions', cell: (row) => row.credits_used ?? 0 },
                  {
                    key: 'status',
                    header: 'Attendance',
                    cell: (row) => (
                      <Select
                        aria-label={`Attendance for ${row.player_name ?? row.player_id}`}
                        className="h-8 w-32"
                        placeholder={row.status}
                        value={
                          row.status === 'attended' || row.status === 'no_show'
                            ? row.status
                            : undefined
                        }
                        onValueChange={(value) =>
                          void setAttendance(row, value as 'attended' | 'no_show')
                        }
                        options={[
                          { value: 'attended', label: 'Attended' },
                          { value: 'no_show', label: 'No-show' },
                        ]}
                      />
                    ),
                  },
                  {
                    key: 'actions',
                    header: '',
                    align: 'right',
                    cell: (row) => (
                      <Button
                        variant="ghost"
                        size="sm"
                        disabled={row.status === 'cancelled'}
                        onClick={() => {
                          setPendingBooking(row);
                          setOutcome('auto');
                          setRefundPct(0);
                          setBookingReason('');
                        }}
                      >
                        Cancel
                      </Button>
                    ),
                  },
                ]}
                data={roster}
              />
            )}
          </CardContent>
        </Card>
      </QueryState>

      <BookOnBehalfDialog
        open={bookOpen}
        onOpenChange={setBookOpen}
        sessionId={sessionId}
        seatsLeft={detail?.seats_left}
        onBooked={() => void rosterQuery.refetch()}
      />

      <Modal
        open={pendingBooking !== null}
        onOpenChange={(open) => !open && setPendingBooking(null)}
        title="Cancel booking"
        description="Choose the outcome. Leave on the policy default unless you need to override."
        footer={
          <>
            <Button variant="outline" onClick={() => setPendingBooking(null)}>
              Keep booking
            </Button>
            <Button
              variant="danger"
              onClick={() => void confirmCancelBooking()}
              disabled={cancelBooking.isPending}
            >
              Cancel booking
            </Button>
          </>
        }
      >
        <div className="flex flex-col gap-4">
          <div className="rounded-md border border-border p-3 text-sm" data-testid="cancel-preview">
            <p className="font-medium">Outcome preview</p>
            <p className="text-muted-foreground">
              {pendingBooking?.payment_method === 'credits'
                ? `${pendingBooking?.credits_used ?? 0} session(s) will be handled per the selected outcome.`
                : 'Any card refund is processed after confirmation.'}
              {outcome === 'partial_refund' ? ` Partial refund of ${refundPct}%.` : ''}
            </p>
          </div>
          <FormField label="Outcome">
            <Select
              aria-label="Outcome"
              value={outcome}
              onValueChange={setOutcome}
              options={CANCEL_OUTCOMES.map((option) => ({ ...option }))}
            />
          </FormField>
          {outcome === 'partial_refund' ? (
            <FormField label="Refund percent">
              <Input
                type="number"
                value={refundPct}
                onChange={(event) => setRefundPct(Number(event.target.value))}
              />
            </FormField>
          ) : null}
          <FormField label="Reason">
            <Input
              value={bookingReason}
              onChange={(event) => setBookingReason(event.target.value)}
            />
          </FormField>
        </div>
      </Modal>

      <Modal
        open={rescheduleOpen}
        onOpenChange={setRescheduleOpen}
        title="Reschedule session"
        footer={
          <>
            <Button variant="outline" onClick={() => setRescheduleOpen(false)}>
              Cancel
            </Button>
            <Button onClick={() => void submitReschedule()} disabled={reschedule.isPending}>
              Save new time
            </Button>
          </>
        }
      >
        <div className="grid gap-4 sm:grid-cols-2">
          <FormField label="New date">
            <Input
              type="date"
              value={rescheduleDate}
              onChange={(event) => setRescheduleDate(event.target.value)}
            />
          </FormField>
          <FormField label={`New time (${timezone})`}>
            <TimePicker
              value={rescheduleTime}
              onChange={(event) => setRescheduleTime(event.target.value)}
            />
          </FormField>
        </div>
      </Modal>

      <Modal
        open={editOpen}
        onOpenChange={setEditOpen}
        title="Edit session"
        footer={
          <>
            <Button variant="outline" onClick={() => setEditOpen(false)}>
              Cancel
            </Button>
            <Button
              onClick={() => void submitEdit()}
              disabled={updateSession.isPending || editSeries.isPending}
            >
              Save
            </Button>
          </>
        }
      >
        <div className="flex flex-col gap-4">
          {isSeries ? (
            <FormField label="Apply to">
              <Select
                aria-label="Apply to"
                value={editScope}
                onValueChange={(value) => setEditScope(value as typeof editScope)}
                options={[
                  { value: 'single', label: 'This session only' },
                  { value: 'following', label: 'This and following' },
                  { value: 'all', label: 'Entire series' },
                ]}
              />
            </FormField>
          ) : null}
          <FormField label="Capacity">
            <Input
              type="number"
              defaultValue={session?.capacity ?? 1}
              onChange={(event) => setEditCapacity(Number(event.target.value))}
            />
          </FormField>
          <Switch
            label="Published"
            checked={editVisibility === 'public'}
            onCheckedChange={(checked) => setEditVisibility(checked ? 'public' : 'hidden')}
          />
          <Switch
            label="Show coach names to customers"
            checked={editShowCoaches}
            onCheckedChange={setEditShowCoaches}
          />
        </div>
      </Modal>

      <Modal
        open={cancelSessionOpen}
        onOpenChange={setCancelSessionOpen}
        title="Cancel session?"
        description="All booked customers will be notified and cancelled per the policy."
        footer={
          <>
            <Button variant="outline" onClick={() => setCancelSessionOpen(false)}>
              Keep session
            </Button>
            <Button
              variant="danger"
              onClick={() => void confirmCancelSession()}
              disabled={cancelSession.isPending}
            >
              Cancel session
            </Button>
          </>
        }
      >
        <FormField label="Reason (optional)">
          <Input
            aria-label="Cancellation reason"
            value={cancelReason}
            onChange={(event) => setCancelReason(event.target.value)}
          />
        </FormField>
      </Modal>
    </div>
  );
}
