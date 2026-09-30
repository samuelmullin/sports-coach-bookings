import { Link } from 'react-router-dom';
import { FileText, PenLine } from 'lucide-react';
import { Badge, Button, Card, CardContent, EmptyState } from '@scb/ui';
import { usePlayerWaivers, type PlayerWaiverStatusResponse } from '../../api/endpoints';
import { body, errorMessage } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { VenueTime } from '../shared/VenueTime';

export function PlayerWaiversSection({
  playerId,
  timezone,
}: {
  playerId: string;
  timezone: string;
}) {
  const query = usePlayerWaivers(playerId);
  const status = body<PlayerWaiverStatusResponse>(query);
  const waivers = status?.waivers ?? [];

  return (
    <QueryState
      loading={query.isLoading}
      error={query.isError ? errorMessage(query.error) : undefined}
      onRetry={() => void query.refetch()}
    >
      {waivers.length === 0 ? (
        <EmptyState title="No waivers" description="This player has no waivers to sign." />
      ) : (
        <ul className="flex flex-col gap-2">
          {waivers.map((waiver) => (
            <li key={waiver.version_id}>
              <Card>
                <CardContent className="flex flex-wrap items-center justify-between gap-3 pt-4">
                  <div className="flex flex-col gap-0.5">
                    <span className="flex items-center gap-2 font-medium">
                      <FileText className="h-4 w-4" aria-hidden="true" />
                      {waiver.name}
                    </span>
                    {waiver.signed && waiver.signed_at ? (
                      <VenueTime
                        instant={waiver.signed_at}
                        timezone={timezone}
                        pattern="MMM d, yyyy"
                        className="text-sm text-muted-foreground"
                      />
                    ) : (
                      <span className="text-sm text-muted-foreground">
                        {waiver.required ? 'Required before booking' : 'Optional'}
                      </span>
                    )}
                  </div>
                  <div className="flex items-center gap-2">
                    {waiver.signed ? (
                      <Badge variant="success">Signed</Badge>
                    ) : (
                      <Badge variant={waiver.required ? 'warning' : 'outline'}>
                        {waiver.required ? 'Required' : 'Optional'}
                      </Badge>
                    )}
                    <Button asChild size="sm" variant={waiver.signed ? 'outline' : 'primary'}>
                      <Link to={`/players/${playerId}/waivers/${waiver.version_id}/sign`}>
                        <PenLine className="h-4 w-4" aria-hidden="true" />
                        {waiver.signed ? 'Sign again' : 'Read & sign'}
                      </Link>
                    </Button>
                  </div>
                </CardContent>
              </Card>
            </li>
          ))}
        </ul>
      )}
    </QueryState>
  );
}
