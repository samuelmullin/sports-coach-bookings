import { Link, useLocation, useParams } from 'react-router-dom';
import { ArrowLeft, CalendarDays, Clock, MapPin, Users } from 'lucide-react';
import { Badge, Button, Card, CardContent, CardHeader, CardTitle } from '@scb/ui';
import {
  sessionQueryKey,
  useSession,
  type SessionDetail,
  type NotBookableReason,
} from '../../api/endpoints';
import { body, errorCode, errorMessage } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { Money } from '../shared/Money';
import { VenueTime, TimezoneNote } from '../shared/VenueTime';
import { usePortalSettings } from '../shared/extras';
import { AddToCartButton } from '../cart/AddToCartButton';
import { OfferingPacks } from './OfferingPacks';
import { useCustomerAuth } from '../../auth/customer-auth';

const FORMAT_LABEL: Record<string, string> = {
  private: 'Private',
  semi_private: 'Semi-private',
  group: 'Group',
};

const REASON_LABEL: Record<string, string> = {
  full: 'This session is full',
  too_late: 'Booking for this session has closed',
  too_early: 'Booking for this session has not opened yet',
  cancelled: 'This session was cancelled',
};

export function SessionDetailPage() {
  const { sessionId } = useParams<{ sessionId: string }>();
  const location = useLocation();
  const { status } = useCustomerAuth();
  const settings = usePortalSettings();
  const authenticated = status === 'authenticated';

  const query = useSession(sessionId ?? '', {
    query: {
      queryKey: sessionQueryKey(sessionId ?? ''),
      enabled: Boolean(sessionId),
      retry: false,
    },
  });

  const entry = body<SessionDetail>(query);
  const session = entry?.session;
  const offering = entry?.offering;
  const venue = entry?.venue;
  const timezone = venue?.timezone ?? 'UTC';
  const backTo = '/schedule';
  const from = location.pathname;

  const seatsLeft = entry?.seats_left ?? session?.seats_left ?? 0;
  const capacity = session?.capacity ?? offering?.default_capacity ?? 0;
  const bookable = Boolean(entry?.bookable) && !entry?.already_booked;
  const reason = entry?.not_bookable_reason as NotBookableReason | undefined;

  return (
    <div className="flex flex-col gap-4">
      <Button asChild variant="ghost" size="sm" className="self-start">
        <Link to={backTo}>
          <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Back to schedule
        </Link>
      </Button>

      <QueryState
        loading={query.isLoading}
        error={
          query.isError && errorCode(query.error) !== 'not_found'
            ? errorMessage(query.error)
            : undefined
        }
        onRetry={() => void query.refetch()}
      >
        {!entry || !session ? (
          <p className="text-sm text-muted-foreground">
            This session is no longer available. It may have been cancelled or already happened.
          </p>
        ) : (
          <>
            <PageHeader
              title={offering?.name ?? session.title_override ?? 'Session'}
              description={offering?.description ?? undefined}
              actions={
                bookable ? (
                  authenticated ? (
                    <Button asChild>
                      <Link to={`/book/${session.id}`}>Book this session</Link>
                    </Button>
                  ) : (
                    <>
                      <AddToCartButton
                        type="drop_in"
                        refId={session.id ?? ''}
                        title={offering?.name ?? session.title_override ?? 'Session'}
                        priceMinor={offering?.drop_in_price ?? undefined}
                        currency={settings.currency}
                        sessionId={session.id}
                        startsAt={session.starts_at ?? undefined}
                        venueName={venue?.name ?? undefined}
                      />
                      <Button asChild variant="outline">
                        <Link to="/register" state={{ from }}>
                          Register to book
                        </Link>
                      </Button>
                    </>
                  )
                ) : undefined
              }
            />

            <Card>
              <CardContent className="flex flex-col gap-3 pt-4">
                {offering?.format ? (
                  <Badge variant="outline" className="self-start">
                    {FORMAT_LABEL[offering.format] ?? offering.format}
                  </Badge>
                ) : null}
                <div className="flex items-center gap-2 text-sm font-medium">
                  <CalendarDays className="h-4 w-4" aria-hidden="true" />
                  {session.starts_at ? (
                    <VenueTime instant={session.starts_at} timezone={timezone} />
                  ) : (
                    <span>Time to be announced</span>
                  )}
                </div>
                <TimezoneNote timezone={timezone} />
                <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-muted-foreground">
                  {venue?.name ? (
                    <span className="flex items-center gap-1">
                      <MapPin className="h-3.5 w-3.5" aria-hidden="true" />
                      {venue.name}
                    </span>
                  ) : null}
                  {offering?.duration_minutes ? (
                    <span className="flex items-center gap-1">
                      <Clock className="h-3.5 w-3.5" aria-hidden="true" />
                      {offering.duration_minutes} min
                    </span>
                  ) : null}
                  <span className="flex items-center gap-1">
                    <Users className="h-3.5 w-3.5" aria-hidden="true" />
                    {seatsLeft > 0 ? `${seatsLeft} of ${capacity} seats left` : 'No seats left'}
                  </span>
                </div>

                {entry.coaches && entry.coaches.length > 0 ? (
                  <p className="text-sm text-muted-foreground">
                    Coach{entry.coaches.length > 1 ? 'es' : ''}:{' '}
                    {entry.coaches
                      .map((coach) => coach.display_name)
                      .filter(Boolean)
                      .join(', ')}
                  </p>
                ) : null}

                <div className="flex flex-wrap items-center gap-2 border-t border-border pt-3 text-sm">
                  {typeof offering?.credit_cost === 'number' && offering.credit_cost > 0 ? (
                    <Badge variant="accent">
                      {offering.credit_cost} session{offering.credit_cost === 1 ? '' : 's'}
                    </Badge>
                  ) : null}
                  {typeof offering?.drop_in_price === 'number' ? (
                    <span className="flex items-center gap-1">
                      Drop-in <Money amountMinor={offering.drop_in_price} className="font-medium" />
                    </span>
                  ) : null}
                  {entry.already_booked ? (
                    <Badge variant="success">Already booked</Badge>
                  ) : reason ? (
                    <Badge variant="outline">{REASON_LABEL[reason] ?? reason}</Badge>
                  ) : null}
                </div>
              </CardContent>
            </Card>

            {offering?.id ? (
              <OfferingPacks
                offeringId={offering.id}
                offeringName={offering.name}
                dropInPrice={offering.drop_in_price}
                creditCost={offering.credit_cost}
              />
            ) : null}

            {session.notes_public ? (
              <Card>
                <CardHeader>
                  <CardTitle>About this session</CardTitle>
                </CardHeader>
                <CardContent>
                  <p className="whitespace-pre-line text-sm text-muted-foreground">
                    {session.notes_public}
                  </p>
                </CardContent>
              </Card>
            ) : null}

            {!authenticated ? (
              <Card className="border-primary/40 bg-primary/5">
                <CardHeader>
                  <CardTitle>New here?</CardTitle>
                </CardHeader>
                <CardContent className="flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                  <p className="text-sm text-muted-foreground">
                    Create a free account to book this session, manage your players, and track
                    sessions.
                  </p>
                  <div className="flex flex-wrap gap-2">
                    <Button asChild>
                      <Link to="/register" state={{ from }}>
                        Create an account
                      </Link>
                    </Button>
                    <Button asChild variant="outline">
                      <Link to="/login" state={{ from }}>
                        Sign in
                      </Link>
                    </Button>
                  </div>
                </CardContent>
              </Card>
            ) : null}
          </>
        )}
      </QueryState>
    </div>
  );
}
