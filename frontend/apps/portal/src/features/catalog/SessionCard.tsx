import { Link, useNavigate } from 'react-router-dom';
import { Badge, Button, Card, CardContent } from '@scb/ui';
import { MapPin, Users } from 'lucide-react';
import type { SessionListItem } from '../../api/endpoints';
import { Money } from '../shared/Money';
import { VenueTime } from '../shared/VenueTime';

const FORMAT_LABEL: Record<string, string> = {
  private: 'Private',
  semi_private: 'Semi-private',
  group: 'Group',
};

const REASON_LABEL: Record<string, string> = {
  full: 'Full',
  too_late: 'Booking closed',
  too_early: 'Not open yet',
  cancelled: 'Cancelled',
};

export function SessionCard({
  item,
  timezone,
  canBook,
  creditCost,
  dropInPrice,
}: {
  item: SessionListItem;
  timezone: string;
  canBook: boolean;
  creditCost?: number;
  dropInPrice?: number;
}) {
  const session = item.session;
  const offering = item.offering;
  const venue = item.venue;
  const startsAt = session?.starts_at ?? undefined;
  const seatsLeft = item.seats_left ?? session?.seats_left ?? 0;
  const capacity = session?.capacity ?? offering?.default_capacity ?? 0;
  const coaches = item.coaches ?? [];
  const bookable = item.bookable ?? false;
  const reason = item.not_bookable_reason ?? undefined;
  const navigate = useNavigate();
  const detailHref = session?.id ? `/sessions/${session.id}` : undefined;

  return (
    <Card
      data-testid="session-card"
      onClick={detailHref ? () => navigate(detailHref) : undefined}
      className={
        detailHref ? 'cursor-pointer transition-colors hover:border-primary/50' : undefined
      }
    >
      <CardContent className="flex flex-col gap-3 pt-4">
        <div className="flex items-start justify-between gap-3">
          <div className="flex flex-col gap-0.5">
            <h3 className="font-medium">
              {detailHref ? (
                <Link
                  to={detailHref}
                  onClick={(clickEvent) => clickEvent.stopPropagation()}
                  className="hover:underline"
                >
                  {offering?.name ?? session?.title_override ?? 'Session'}
                </Link>
              ) : (
                (offering?.name ?? session?.title_override ?? 'Session')
              )}
            </h3>
            {startsAt ? (
              <VenueTime
                instant={startsAt}
                timezone={timezone}
                className="text-sm text-muted-foreground"
              />
            ) : (
              <span className="text-sm text-muted-foreground">Time to be announced</span>
            )}
          </div>
          {offering?.format ? (
            <Badge variant="outline">{FORMAT_LABEL[offering.format] ?? offering.format}</Badge>
          ) : null}
        </div>

        {offering?.description ? (
          <p className="line-clamp-2 text-sm text-muted-foreground">{offering.description}</p>
        ) : null}

        <div className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm text-muted-foreground">
          {venue?.name ? (
            <span className="flex items-center gap-1">
              <MapPin className="h-3.5 w-3.5" aria-hidden="true" />
              {venue.name}
            </span>
          ) : null}
          <span className="flex items-center gap-1">
            <Users className="h-3.5 w-3.5" aria-hidden="true" />
            {seatsLeft > 0 ? `${seatsLeft} of ${capacity} seats left` : 'No seats left'}
          </span>
          {coaches.length > 0 ? (
            <span>
              {coaches
                .map((coach) => coach.display_name)
                .filter(Boolean)
                .join(', ')}
            </span>
          ) : null}
        </div>

        <div className="flex flex-wrap items-center justify-between gap-2">
          <div className="flex flex-wrap items-center gap-2 text-sm">
            {typeof creditCost === 'number' && creditCost > 0 ? (
              <Badge variant="accent">
                {creditCost} session{creditCost === 1 ? '' : 's'}
              </Badge>
            ) : null}
            {typeof dropInPrice === 'number' ? (
              <Money amountMinor={dropInPrice} className="font-medium" />
            ) : creditCost ? null : (
              <span className="text-muted-foreground">See club for pricing</span>
            )}
            {item.already_booked ? <Badge variant="success">Already booked</Badge> : null}
          </div>

          {bookable && canBook && session?.id ? (
            <Button asChild size="sm">
              <Link
                to={`/book/${session.id}`}
                onClick={(clickEvent) => clickEvent.stopPropagation()}
              >
                Book
              </Link>
            </Button>
          ) : bookable && !canBook ? (
            <Button asChild size="sm" variant="outline">
              <Link
                to={offering?.id ? `/offerings/${offering.id}/schedule` : '/login'}
                onClick={(clickEvent) => clickEvent.stopPropagation()}
              >
                Book now
              </Link>
            </Button>
          ) : (
            <Badge variant="outline">
              {reason ? (REASON_LABEL[reason] ?? reason) : 'Unavailable'}
            </Badge>
          )}
        </div>
      </CardContent>
    </Card>
  );
}
