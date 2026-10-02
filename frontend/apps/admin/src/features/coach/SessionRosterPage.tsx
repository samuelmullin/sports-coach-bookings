import { useMemo, useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Check, ShieldAlert, UserX } from 'lucide-react';
import { useQueryClient } from '@tanstack/react-query';
import { ApiError } from '@scb/api-client';
import { Badge, Button, Card, CardContent, ConfirmDialog, EmptyState, cn, useToast } from '@scb/ui';
import {
  coachRosterQueryKey,
  useCoachSessionRoster,
  useCoachSessions,
  useMarkAttendance,
} from '../../api/endpoints';
import { errorMessage } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';
import { useTenantSettings } from '../shared/useTenantSettings';
import {
  FEEDBACK_STATUS_LABEL,
  FEEDBACK_STATUS_VARIANT,
  coachRosterItems,
  coachSessionItems,
  feedbackStatus,
  isForbidden,
  playerDisplayName,
  rosterFeedback,
  rosterPlayer,
  sessionTime,
  sessionTitle,
} from './coach-utils';
import { FeedbackComposer } from './FeedbackComposer';
import type { CoachFeedbackSummary, CoachRosterEntry } from './types';

interface AttendanceUpdate {
  booking_id: string;
  status: 'attended' | 'no_show';
}

/** Clone the cached roster query, replacing statuses for the given bookings. */
function withStatuses(previous: unknown, updates: AttendanceUpdate[]): unknown {
  const envelope = previous as
    { data?: { data?: { data?: CoachRosterEntry[] } } } | undefined | null;
  if (!envelope?.data?.data?.data) return previous;
  const byId = new Map(updates.map((update) => [update.booking_id, update.status]));
  const data = envelope.data.data.data.map((entry) =>
    byId.has(entry.booking_id) ? { ...entry, status: byId.get(entry.booking_id) as string } : entry,
  );
  return { ...envelope, data: { ...envelope.data, data: { ...envelope.data.data, data } } };
}

function latestFeedback(entry: CoachRosterEntry): CoachFeedbackSummary | undefined {
  const summaries = rosterFeedback(entry);
  if (summaries.length === 0) return undefined;
  return [...summaries].sort((a, b) => {
    if (a.visibility === 'shared' && b.visibility !== 'shared') return -1;
    if (b.visibility === 'shared' && a.visibility !== 'shared') return 1;
    return 0;
  })[0];
}

export function SessionRosterPage() {
  const { sessionId = '' } = useParams();
  const navigate = useNavigate();
  const { timezone } = useTenantSettings();
  const { toast } = useToast();
  const queryClient = useQueryClient();

  const query = useCoachSessionRoster(sessionId);
  const sessionsQuery = useCoachSessions();
  const markAttendance = useMarkAttendance({
    mutation: {
      retry: (count, error) => !(error instanceof ApiError && error.status < 500) && count < 2,
    },
  });
  const rosterKey = coachRosterQueryKey(sessionId);

  const roster = coachRosterItems(query);
  const session = useMemo(
    () => coachSessionItems(sessionsQuery).find((entry) => entry.session?.id === sessionId),
    [sessionsQuery, sessionId],
  );

  const [noShowTarget, setNoShowTarget] = useState<CoachRosterEntry | null>(null);
  const [composerEntry, setComposerEntry] = useState<CoachRosterEntry | null>(null);

  const submitAttendance = async (updates: AttendanceUpdate[]) => {
    if (updates.length === 0) return;
    const previous = queryClient.getQueryData(rosterKey);
    queryClient.setQueryData(rosterKey, withStatuses(previous, updates));
    try {
      const result = await markAttendance.mutateAsync({
        sessionId,
        data: { attendance: updates },
      });
      const rows =
        (
          result as {
            data?: { data?: { data?: { ok?: boolean; error?: string | null }[] } };
          }
        ).data?.data?.data ?? [];
      const failed = rows.filter((row) => row.ok === false);
      if (failed.length > 0) {
        toast({
          title: `${failed.length} attendance change(s) were rejected`,
          description: failed[0]?.error ?? undefined,
          variant: 'danger',
        });
      } else {
        toast({ title: 'Attendance saved', variant: 'success' });
      }
      void query.refetch();
    } catch (error) {
      queryClient.setQueryData(rosterKey, previous);
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  const markAllPresent = () => {
    const updates = roster
      .filter((entry) => entry.status !== 'attended' && entry.status !== 'cancelled')
      .map((entry) => ({ booking_id: entry.booking_id, status: 'attended' as const }));
    void submitAttendance(updates);
  };

  if (isForbidden(query.error)) {
    return (
      <EmptyState
        icon={<ShieldAlert className="h-8 w-8" />}
        title="Not on your roster"
        description="You are not assigned to this session, so its roster is not available."
        action={
          <Button asChild variant="outline">
            <Link to="/my-sessions">Back to my sessions</Link>
          </Button>
        }
      />
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title={session ? sessionTitle(session) : 'Session roster'}
        description={
          session
            ? `${sessionTime(session, timezone)}${session.venue?.name ? ` · ${session.venue.name}` : ''}`
            : undefined
        }
        actions={
          <div className="flex flex-wrap gap-2">
            <Button variant="outline" size="sm" onClick={() => navigate('/my-sessions')}>
              <ArrowLeft className="h-4 w-4" aria-hidden="true" />
              Back
            </Button>
            <Button
              size="sm"
              onClick={markAllPresent}
              disabled={markAttendance.isPending || roster.length === 0}
            >
              <Check className="h-4 w-4" aria-hidden="true" />
              Mark all present
            </Button>
          </div>
        }
      />

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {roster.length === 0 ? (
          <EmptyState
            title="No players booked"
            description="Nobody is booked into this session yet."
          />
        ) : (
          <div className="grid gap-3 lg:grid-cols-2">
            {roster.map((entry) => {
              const player = rosterPlayer(entry);
              const name = playerDisplayName(player, entry.player_id);
              const status = feedbackStatus(rosterFeedback(entry));
              const attended = entry.status === 'attended';
              const noShow = entry.status === 'no_show';
              return (
                <Card key={entry.booking_id} data-testid="roster-row">
                  <CardContent className="flex flex-col gap-3 pt-4">
                    <div className="flex items-start justify-between gap-3">
                      <div className="flex flex-col gap-1">
                        <Link
                          to={`/players/${entry.player_id}`}
                          className="text-base font-semibold hover:underline"
                        >
                          {name}
                        </Link>
                        <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
                          {typeof player?.age === 'number' ? <span>Age {player.age}</span> : null}
                          {player?.preferred_positions?.length ? (
                            <span>{player.preferred_positions.join(', ')}</span>
                          ) : null}
                        </div>
                        {player?.emergency_contact ? (
                          <p className="text-xs text-muted-foreground">
                            Emergency contact: {player.emergency_contact.name}
                            {player.emergency_contact.phone
                              ? ` · ${player.emergency_contact.phone}`
                              : ''}
                          </p>
                        ) : null}
                      </div>
                      {player?.has_medical_info ? (
                        <Badge variant="warning">Medical info on file</Badge>
                      ) : null}
                    </div>

                    <div className="flex flex-wrap items-center gap-2">
                      <Badge variant={attended ? 'success' : noShow ? 'danger' : 'outline'}>
                        {attended ? 'Attended' : noShow ? 'No-show' : 'Not marked'}
                      </Badge>
                      <Badge variant={FEEDBACK_STATUS_VARIANT[status]}>
                        {FEEDBACK_STATUS_LABEL[status]}
                      </Badge>
                    </div>

                    <div className="flex flex-wrap gap-2">
                      <Button
                        size="sm"
                        variant={attended ? 'primary' : 'outline'}
                        aria-label={`Mark ${name} attended`}
                        aria-pressed={attended}
                        onClick={() =>
                          void submitAttendance([
                            { booking_id: entry.booking_id, status: 'attended' },
                          ])
                        }
                        disabled={markAttendance.isPending}
                      >
                        <Check className="h-4 w-4" aria-hidden="true" />
                        Attended
                      </Button>
                      <Button
                        size="sm"
                        variant={noShow ? 'danger' : 'outline'}
                        aria-label={`Mark ${name} no-show`}
                        aria-pressed={noShow}
                        onClick={() => setNoShowTarget(entry)}
                        disabled={markAttendance.isPending}
                      >
                        <UserX className="h-4 w-4" aria-hidden="true" />
                        No-show
                      </Button>
                      <Button
                        size="sm"
                        variant="outline"
                        className={cn('ml-auto', status === 'shared' && 'border-green-300')}
                        aria-label={`Feedback for ${name}`}
                        onClick={() => setComposerEntry(entry)}
                      >
                        {status === 'none' ? 'Add feedback' : 'Edit feedback'}
                      </Button>
                    </div>
                  </CardContent>
                </Card>
              );
            })}
          </div>
        )}
      </QueryState>

      <ConfirmDialog
        open={noShowTarget !== null}
        onOpenChange={(open) => !open && setNoShowTarget(null)}
        title="Mark as no-show?"
        description="This applies the session's no-show policy and may affect the family's sessions. This cannot be undone."
        confirmLabel="Mark no-show"
        destructive
        loading={markAttendance.isPending}
        onConfirm={() => {
          if (noShowTarget) {
            void submitAttendance([{ booking_id: noShowTarget.booking_id, status: 'no_show' }]);
          }
          setNoShowTarget(null);
        }}
      />

      {composerEntry ? (
        <FeedbackComposer
          open={composerEntry !== null}
          onOpenChange={(open) => !open && setComposerEntry(null)}
          sessionId={sessionId}
          playerId={composerEntry.player_id}
          playerName={playerDisplayName(rosterPlayer(composerEntry), composerEntry.player_id)}
          feedbackId={latestFeedback(composerEntry)?.id ?? null}
          onSaved={() => void query.refetch()}
        />
      ) : null}
    </div>
  );
}
