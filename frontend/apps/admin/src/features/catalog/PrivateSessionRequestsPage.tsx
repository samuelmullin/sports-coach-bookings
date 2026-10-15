import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import { Button, Card, CardContent, EmptyState, FormField, Input, Select, useToast } from '@scb/ui';
import {
  useOfferings,
  usePrivateSessionRequests,
  useReviewPrivateSessionRequest,
  useSessions,
  type SessionSummary,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';

interface PrivateRequest {
  id: string;
  offering_id: string;
  household_id: string;
  player_count: number;
  preferred_times?: string[];
  notes?: string | null;
  status: string;
  inserted_at?: string;
}

function isoDate(date: Date) {
  return date.toISOString().slice(0, 10);
}

export function PrivateSessionRequestsPage() {
  const { toast } = useToast();
  const requestsQuery = usePrivateSessionRequests({ status: 'pending' });
  const offeringsQuery = useOfferings();
  const range = useMemo(() => {
    const from = new Date();
    const to = new Date();
    to.setFullYear(to.getFullYear() + 1);
    return { from: isoDate(from), to: isoDate(to) };
  }, []);
  const sessionsQuery = useSessions(range);
  const review = useReviewPrivateSessionRequest();
  const requests = listItems<PrivateRequest>(requestsQuery);
  const offerings = listItems<{ id: string; name: string }>(offeringsQuery);
  const sessions = listItems<SessionSummary>(sessionsQuery);
  const [selected, setSelected] = useState<Record<string, string>>({});
  const [declineReasons, setDeclineReasons] = useState<Record<string, string>>({});

  const reviewRequest = async (request: PrivateRequest, status: 'approved' | 'declined') => {
    try {
      await review.mutateAsync({
        id: request.id,
        data: {
          status,
          ...(status === 'approved' ? { session_id: selected[request.id] } : {}),
          ...(status === 'declined' ? { decline_reason: declineReasons[request.id] || null } : {}),
        },
      });
      toast({
        title: status === 'approved' ? 'Private session approved' : 'Request declined',
        variant: 'success',
      });
      await requestsQuery.refetch();
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Private session requests"
        description="Create an empty session on the schedule, then assign it to a pending private request."
        actions={
          <Button asChild variant="outline">
            <Link to="/schedule">Open schedule</Link>
          </Button>
        }
      />
      <QueryState
        loading={requestsQuery.isLoading || offeringsQuery.isLoading || sessionsQuery.isLoading}
        error={requestsQuery.isError ? errorMessage(requestsQuery.error) : undefined}
        onRetry={() => void requestsQuery.refetch()}
      >
        {requests.length === 0 ? (
          <EmptyState
            title="No pending requests"
            description="New customer requests will appear here."
          />
        ) : (
          <ul className="flex flex-col gap-3">
            {requests.map((request) => {
              const offeringName =
                offerings.find((item) => item.id === request.offering_id)?.name ?? 'Offering';
              const available = sessions.filter((item) => {
                const session = item.session;
                return (
                  session?.offering_id === request.offering_id &&
                  session.status === 'scheduled' &&
                  session.access_mode === 'public' &&
                  (session.booked_count ?? 0) + (session.held_count ?? 0) === 0
                );
              });
              return (
                <li key={request.id}>
                  <Card>
                    <CardContent className="flex flex-col gap-3 pt-4">
                      <div>
                        <h3 className="font-medium">
                          {offeringName} · {request.player_count} players
                        </h3>
                        {request.notes ? (
                          <p className="text-sm text-muted-foreground">{request.notes}</p>
                        ) : null}
                        {request.preferred_times?.length ? (
                          <p className="text-sm text-muted-foreground">
                            Preferred:{' '}
                            {request.preferred_times
                              .map((time) => new Date(time).toLocaleString())
                              .join(', ')}
                          </p>
                        ) : null}
                      </div>
                      <Select
                        aria-label={`Session for ${offeringName}`}
                        value={selected[request.id] ?? ''}
                        onValueChange={(value) =>
                          setSelected((current) => ({ ...current, [request.id]: value }))
                        }
                        options={[
                          { value: '', label: 'Choose an empty scheduled session' },
                          ...available.map((item) => ({
                            value: item.session?.id ?? '',
                            label: item.session?.starts_at
                              ? new Date(item.session.starts_at).toLocaleString()
                              : 'Session',
                          })),
                        ]}
                      />
                      <FormField label="Decline reason (included in the customer email)">
                        <Input
                          value={declineReasons[request.id] ?? ''}
                          onChange={(event) =>
                            setDeclineReasons((current) => ({
                              ...current,
                              [request.id]: event.target.value,
                            }))
                          }
                          placeholder="Optional"
                        />
                      </FormField>
                      <div className="flex gap-2">
                        <Button
                          disabled={!selected[request.id] || review.isPending}
                          onClick={() => void reviewRequest(request, 'approved')}
                        >
                          Approve and assign
                        </Button>
                        <Button
                          variant="outline"
                          disabled={review.isPending}
                          onClick={() => void reviewRequest(request, 'declined')}
                        >
                          Decline
                        </Button>
                      </div>
                    </CardContent>
                  </Card>
                </li>
              );
            })}
          </ul>
        )}
      </QueryState>
    </div>
  );
}
