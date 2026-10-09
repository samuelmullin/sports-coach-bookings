import { Link } from 'react-router-dom';
import { Badge, Button, Card, CardContent, EmptyState } from '@scb/ui';
import {
  useOfferings,
  usePrivateSessionRequests,
  type PrivateSessionRequest,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';

const STATUS_VARIANT: Record<string, 'success' | 'warning' | 'outline' | 'danger'> = {
  pending: 'warning',
  approved: 'success',
  declined: 'danger',
  cancelled: 'outline',
};

export function PrivateSessionRequestsPage() {
  const query = usePrivateSessionRequests();
  const offeringsQuery = useOfferings();
  const requests = listItems<PrivateSessionRequest>(query);
  const offerings = listItems<{ id: string; name: string }>(offeringsQuery);

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Private session requests"
        description="Track requests awaiting review and see the operator's decision."
        actions={
          <Button asChild variant="outline">
            <Link to="/schedule">Browse offerings</Link>
          </Button>
        }
      />
      <QueryState
        loading={query.isLoading || offeringsQuery.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {requests.length === 0 ? (
          <EmptyState
            title="No private session requests"
            description="Offerings that support private requests will show that option on their details page."
          />
        ) : (
          <ul className="flex flex-col gap-3">
            {requests.map((request) => {
              const offering = offerings.find((item) => item.id === request.offering_id);
              return (
                <li key={request.id}>
                  <Card>
                    <CardContent className="flex flex-col gap-2 pt-4">
                      <div className="flex flex-wrap items-start justify-between gap-2">
                        <div>
                          <h2 className="font-medium">{offering?.name ?? 'Private session'}</h2>
                          <p className="text-sm text-muted-foreground">
                            {request.player_count} player{request.player_count === 1 ? '' : 's'}
                          </p>
                        </div>
                        <Badge variant={STATUS_VARIANT[request.status] ?? 'outline'}>
                          {request.status}
                        </Badge>
                      </div>
                      {request.preferred_times.length > 0 ? (
                        <p className="text-sm text-muted-foreground">
                          Preferred:{' '}
                          {request.preferred_times
                            .map((time) => new Date(time).toLocaleString())
                            .join(', ')}
                        </p>
                      ) : null}
                      {request.notes ? <p className="text-sm">{request.notes}</p> : null}
                      {request.decline_reason ? (
                        <p className="text-sm text-danger">Reason: {request.decline_reason}</p>
                      ) : null}
                      {request.status === 'approved' && request.session_id ? (
                        <Button asChild size="sm" className="self-start">
                          <Link to={`/sessions/${request.session_id}`}>View scheduled session</Link>
                        </Button>
                      ) : null}
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
