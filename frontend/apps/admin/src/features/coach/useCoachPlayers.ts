import { useCallback, useMemo } from 'react';
import { useQueries } from '@tanstack/react-query';
import { coachRosterQueryOptions, useCoachSessions } from '../../api/endpoints';
import { errorMessage } from '../shared/api-utils';
import { coachRosterItems, coachSessionItems, rosterFeedback, rosterPlayer } from './coach-utils';
import type { CoachPlayerSummary } from './types';

export interface CoachPlayerRow extends CoachPlayerSummary {
  has_feedback: boolean;
  has_medical_info: boolean;
}

const MAX_SESSIONS = 20;

/**
 * Aggregates the players booked into the coach's sessions by fanning out to the
 * per-session roster endpoint. The coach API has no cross-session player list.
 */
export function useCoachPlayers() {
  const sessionsQuery = useCoachSessions();
  const sessionIds = useMemo(
    () =>
      coachSessionItems(sessionsQuery)
        .map((entry) => entry.session?.id)
        .filter((id): id is string => Boolean(id))
        .slice(0, MAX_SESSIONS),
    [sessionsQuery],
  );

  const rosterQueries = useQueries({
    queries: sessionIds.map((sessionId) => coachRosterQueryOptions(sessionId)),
  });

  const players = useMemo(() => {
    const byId = new Map<string, CoachPlayerRow>();
    for (const query of rosterQueries) {
      for (const entry of coachRosterItems(query.data)) {
        const summary = rosterPlayer(entry);
        if (!summary?.id) continue;
        const existing = byId.get(entry.player_id);
        byId.set(entry.player_id, {
          ...summary,
          id: entry.player_id,
          has_feedback: (existing?.has_feedback ?? false) || rosterFeedback(entry).length > 0,
          has_medical_info: Boolean(summary.has_medical_info),
        });
      }
    }
    return [...byId.values()].sort((a, b) => a.name.localeCompare(b.name));
  }, [rosterQueries]);

  const failedRoster = rosterQueries.find((query) => query.isError);
  const loading = sessionsQuery.isLoading || rosterQueries.some((query) => query.isLoading);
  const error = sessionsQuery.isError
    ? errorMessage(sessionsQuery.error)
    : failedRoster
      ? errorMessage(failedRoster.error)
      : undefined;

  const refetch = useCallback(() => {
    void sessionsQuery.refetch();
    for (const query of rosterQueries) void query.refetch();
  }, [sessionsQuery, rosterQueries]);

  return { players, loading, error, refetch };
}
