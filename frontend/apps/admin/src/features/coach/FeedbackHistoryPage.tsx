import { useMemo, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  Badge,
  Button,
  Card,
  CardContent,
  CursorPagination,
  EmptyState,
  Select,
  formatDateTime,
} from '@scb/ui';
import { useFeedbackHistory } from '../../api/endpoints';
import { errorMessage } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';
import { MarkdownPreview } from '../shared/MarkdownPreview';
import { coachFeedbackPage } from './coach-utils';
import { useCursorPager } from '../shared/useCursorPager';
import { useTenantSettings } from '../shared/useTenantSettings';
import { useCoachPlayers } from './useCoachPlayers';
import { FeedbackComposer } from './FeedbackComposer';
import type { CoachFeedbackRecord } from './types';

export function FeedbackHistoryPage() {
  const { timezone } = useTenantSettings();
  const [playerId, setPlayerId] = useState('');
  const pager = useCursorPager(25);
  const { players } = useCoachPlayers();

  const query = useFeedbackHistory({
    player_id: playerId || undefined,
    cursor: pager.cursor,
    limit: pager.limit,
  });
  const page = coachFeedbackPage(query);

  const nameById = useMemo(
    () => new Map(players.map((player) => [player.id, player.name])),
    [players],
  );

  const [editing, setEditing] = useState<CoachFeedbackRecord | null>(null);

  return (
    <div className="flex flex-col gap-4">
      <PageHeader title="Feedback" description="Everything you have written, newest first." />

      <div className="max-w-xs">
        <Select
          aria-label="Filter by player"
          value={playerId}
          onValueChange={(value) => {
            setPlayerId(value);
            pager.reset();
          }}
          options={[
            { value: '', label: 'All players' },
            ...players.map((player) => ({ value: player.id, label: player.name })),
          ]}
        />
      </div>

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {page.data.length === 0 ? (
          <EmptyState
            title="No feedback yet"
            description="Feedback you write for players will appear here."
          />
        ) : (
          <div className="flex flex-col gap-3">
            {page.data.map((record) => (
              <Card key={record.id}>
                <CardContent className="flex flex-col gap-2 pt-4">
                  <div className="flex flex-wrap items-center justify-between gap-2">
                    <div className="flex flex-wrap items-center gap-2">
                      <Link
                        to={`/players/${record.player_id}`}
                        className="text-sm font-semibold hover:underline"
                      >
                        {nameById.get(record.player_id) ?? record.player_id}
                      </Link>
                      <Badge variant={record.visibility === 'shared' ? 'success' : 'warning'}>
                        {record.visibility === 'shared' ? 'Shared' : 'Draft'}
                      </Badge>
                      {record.inserted_at ? (
                        <span className="text-xs text-muted-foreground">
                          {formatDateTime(record.inserted_at, timezone)}
                        </span>
                      ) : null}
                    </div>
                    <Button variant="outline" size="sm" onClick={() => setEditing(record)}>
                      Edit
                    </Button>
                  </div>
                  <MarkdownPreview markdown={record.body} />
                  {record.focus_next ? (
                    <p className="text-sm">
                      <span className="text-muted-foreground">Focus next: </span>
                      {record.focus_next}
                    </p>
                  ) : null}
                </CardContent>
              </Card>
            ))}
            <CursorPagination
              hasPrevious={pager.hasPrevious}
              hasNext={Boolean(page.next_cursor)}
              onPrevious={pager.goPrevious}
              onNext={() => pager.goNext(page.next_cursor ?? undefined)}
            />
          </div>
        )}
      </QueryState>

      {editing ? (
        <FeedbackComposer
          open={editing !== null}
          onOpenChange={(open) => !open && setEditing(null)}
          sessionId={editing.session_id}
          playerId={editing.player_id}
          playerName={nameById.get(editing.player_id) ?? editing.player_id}
          feedbackId={editing.id}
          onSaved={() => void query.refetch()}
        />
      ) : null}
    </div>
  );
}
