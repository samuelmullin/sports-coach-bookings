import { Link } from 'react-router-dom';
import { Badge, Card, CardContent, EmptyState } from '@scb/ui';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';
import { useCoachPlayers } from './useCoachPlayers';

export function CoachPlayersPage() {
  const { players, loading, error, refetch } = useCoachPlayers();

  return (
    <div className="flex flex-col gap-4">
      <PageHeader title="Players" description="Players booked into your sessions." />

      <QueryState loading={loading} error={error} onRetry={refetch}>
        {players.length === 0 ? (
          <EmptyState
            title="No players yet"
            description="Players booked into your sessions will appear here."
          />
        ) : (
          <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
            {players.map((player) => (
              <Link key={player.id} to={`/players/${player.id}`} className="block">
                <Card className="h-full hover:border-primary">
                  <CardContent className="flex h-full flex-col gap-2 pt-4">
                    <span className="text-base font-semibold">{player.name}</span>
                    <div className="flex flex-wrap items-center gap-2 text-sm text-muted-foreground">
                      {typeof player.age === 'number' ? <span>Age {player.age}</span> : null}
                      {player.preferred_positions?.length ? (
                        <span>{player.preferred_positions.join(', ')}</span>
                      ) : null}
                    </div>
                    <div className="mt-auto flex flex-wrap gap-2">
                      {player.has_medical_info ? (
                        <Badge variant="warning">Medical info</Badge>
                      ) : null}
                      {player.has_feedback ? <Badge variant="success">Feedback</Badge> : null}
                    </div>
                  </CardContent>
                </Card>
              </Link>
            ))}
          </div>
        )}
      </QueryState>
    </div>
  );
}
