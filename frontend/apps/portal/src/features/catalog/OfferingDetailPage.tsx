import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { ArrowLeft, CalendarDays, Clock, Users } from 'lucide-react';
import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from '@scb/ui';
import { policyQueryKey, useOfferingPolicy, useOfferings } from '../../api/endpoints';
import { body, errorMessage, listItems } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { OfferingPacks } from './OfferingPacks';
import type { OfferingResponse, PolicySummaryResponse } from '../../api/endpoints';
import { useCustomerAuth } from '../../auth/customer-auth';
import { RequestPrivateSessionDialog } from '../bookings/RequestPrivateSessionDialog';

const FORMAT_LABEL: Record<string, string> = {
  private: 'Private',
  semi_private: 'Semi-private',
  group: 'Group',
};

export function OfferingDetailPage() {
  const { offeringId } = useParams<{ offeringId: string }>();
  const offeringsQuery = useOfferings();
  const policyQuery = useOfferingPolicy(offeringId ?? '', {
    query: {
      queryKey: policyQueryKey(offeringId ?? ''),
      enabled: Boolean(offeringId),
      retry: false,
    },
  });

  const offerings = listItems<OfferingResponse>(offeringsQuery);
  const offering = offerings.find((candidate) => candidate.id === offeringId);
  const policy = body<PolicySummaryResponse>(policyQuery);
  const { status } = useCustomerAuth();
  const [requestPrivate, setRequestPrivate] = useState(false);

  return (
    <div className="flex flex-col gap-4">
      <Button asChild variant="ghost" size="sm" className="self-start">
        <Link to="/schedule">
          <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Back to schedule
        </Link>
      </Button>

      <QueryState
        loading={offeringsQuery.isLoading}
        error={offeringsQuery.isError ? errorMessage(offeringsQuery.error) : undefined}
        onRetry={() => void offeringsQuery.refetch()}
      >
        {!offering ? (
          <p className="text-sm text-muted-foreground">This offering is not available.</p>
        ) : (
          <>
            <PageHeader
              title={offering.name}
              description={offering.description ?? undefined}
              actions={
                <>
                  <Button asChild variant="outline">
                    <Link to={`/schedule?offering=${offering.id}`}>See times</Link>
                  </Button>
                  <Button asChild>
                    <Link to={`/offerings/${offering.id}/schedule`}>Schedule sessions</Link>
                  </Button>
                  {offering.private_enabled && offering.allow_private_requests ? (
                    status === 'authenticated' ? (
                      <Button variant="outline" onClick={() => setRequestPrivate(true)}>
                        Request private session
                      </Button>
                    ) : (
                      <Button asChild variant="outline">
                        <Link to="/login">Sign in to request private</Link>
                      </Button>
                    )
                  ) : null}
                </>
              }
            />

            <div className="flex flex-wrap items-center gap-2">
              <Badge variant="outline">{FORMAT_LABEL[offering.format] ?? offering.format}</Badge>
              <span className="flex items-center gap-1 text-sm text-muted-foreground">
                <Clock className="h-4 w-4" aria-hidden="true" /> {offering.duration_minutes} min
              </span>
              <span className="flex items-center gap-1 text-sm text-muted-foreground">
                <Users className="h-4 w-4" aria-hidden="true" /> Up to {offering.default_capacity}
              </span>
              {offering.min_age != null || offering.max_age != null ? (
                <Badge variant="secondary">
                  Ages {offering.min_age ?? 0}–{offering.max_age ?? '∞'}
                </Badge>
              ) : null}
            </div>

            <OfferingPacks
              offeringId={offering.id}
              offeringName={offering.name}
              dropInPrice={offering.drop_in_price}
              creditCost={offering.credit_cost}
            />

            {policy ? (
              <Card>
                <CardHeader>
                  <CardTitle>Booking policy</CardTitle>
                </CardHeader>
                <CardContent className="flex flex-col gap-1 text-sm text-muted-foreground">
                  <span className="font-medium text-foreground">
                    {policy.policy_name} (v{policy.policy_version})
                  </span>
                  {policy.summary ? <p>{policy.summary}</p> : null}
                </CardContent>
              </Card>
            ) : null}
            {requestPrivate ? (
              <RequestPrivateSessionDialog
                offeringId={offering.id}
                maxPlayers={offering.private_max_players ?? 1}
                open
                onOpenChange={setRequestPrivate}
              />
            ) : null}
          </>
        )}
      </QueryState>

      <Card className="border-dashed">
        <CardContent className="flex items-center gap-2 pt-4 text-sm text-muted-foreground">
          <CalendarDays className="h-4 w-4" aria-hidden="true" />
          <Link className="text-primary hover:underline" to="/schedule">
            Browse all upcoming sessions
          </Link>
        </CardContent>
      </Card>
    </div>
  );
}
