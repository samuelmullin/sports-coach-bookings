import { MessageSquare } from 'lucide-react';
import { Badge, Card, CardContent, EmptyState } from '@scb/ui';
import { usePlayerFeedback, type FeedbackEntry } from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { VenueTime } from '../shared/VenueTime';

const SKILL_LABELS: Record<string, string> = {
  technique: 'Technique',
  effort: 'Effort',
  teamwork: 'Teamwork',
  attitude: 'Attitude',
};

export function FeedbackSection({ playerId, timezone }: { playerId: string; timezone: string }) {
  const query = usePlayerFeedback(playerId);
  const entries = listItems<FeedbackEntry>(query);

  return (
    <QueryState
      loading={query.isLoading}
      error={query.isError ? errorMessage(query.error) : undefined}
      onRetry={() => void query.refetch()}
    >
      {entries.length === 0 ? (
        <EmptyState
          icon={<MessageSquare className="h-8 w-8" />}
          title="No feedback yet"
          description="Coach feedback will appear here after sessions."
        />
      ) : (
        <ol className="flex flex-col gap-3">
          {entries.map((entry) => {
            const ratings = Object.entries(entry.skill_ratings ?? {}).filter(
              ([, value]) => typeof value === 'number',
            );
            return (
              <li key={entry.id}>
                <Card>
                  <CardContent className="flex flex-col gap-2 pt-4">
                    <div className="flex flex-wrap items-center justify-between gap-2">
                      <VenueTime
                        instant={entry.shared_at ?? entry.inserted_at ?? ''}
                        timezone={timezone}
                        pattern="MMM d, yyyy"
                        className="text-sm text-muted-foreground"
                      />
                      <Badge variant="outline">
                        {entry.visibility === 'shared' ? 'Shared' : 'Internal'}
                      </Badge>
                    </div>
                    <p className="whitespace-pre-line text-sm">{entry.body}</p>
                    {entry.focus_next ? (
                      <p className="text-sm">
                        <span className="font-medium">Focus next: </span>
                        {entry.focus_next}
                      </p>
                    ) : null}
                    {ratings.length > 0 ? (
                      <ul className="flex flex-wrap gap-3 text-xs text-muted-foreground">
                        {ratings.map(([skill, value]) => (
                          <li key={skill}>
                            {SKILL_LABELS[skill] ?? skill}: {String(value)}/5
                          </li>
                        ))}
                      </ul>
                    ) : null}
                  </CardContent>
                </Card>
              </li>
            );
          })}
        </ol>
      )}
    </QueryState>
  );
}
