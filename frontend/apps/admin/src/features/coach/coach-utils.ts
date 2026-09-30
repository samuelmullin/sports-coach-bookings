import { ApiError } from '@scb/api-client';
import { formatTimeRange } from '@scb/ui';
import type {
  CoachFeedbackRecord,
  CoachFeedbackSummary,
  CoachPlayerDetail,
  CoachPlayerSummary,
  CoachRosterEntry,
  CoachSessionEntry,
} from './types';

/** Coach session list responses are `{ data: [...] }` (no cursor envelope). */
export function coachSessionItems(query: unknown): CoachSessionEntry[] {
  return (
    (query as { data?: { data?: { data?: CoachSessionEntry[] } } } | undefined)?.data?.data?.data ??
    []
  );
}

export function coachRosterItems(query: unknown): CoachRosterEntry[] {
  return (
    (query as { data?: { data?: { data?: CoachRosterEntry[] } } } | undefined)?.data?.data?.data ??
    []
  );
}

export interface CoachFeedbackPage {
  data: CoachFeedbackRecord[];
  next_cursor?: string | null;
}

export function coachFeedbackPage(query: unknown): CoachFeedbackPage {
  const page = (query as { data?: { data?: CoachFeedbackPage } } | undefined)?.data?.data;
  return { data: page?.data ?? [], next_cursor: page?.next_cursor ?? null };
}

export function coachPlayerBody(query: unknown): CoachPlayerDetail | undefined {
  return (query as { data?: { data?: CoachPlayerDetail } } | undefined)?.data?.data;
}

export function rosterPlayer(entry: CoachRosterEntry): CoachPlayerSummary | null {
  return (entry.player as CoachPlayerSummary | null | undefined) ?? null;
}

export function rosterFeedback(entry: CoachRosterEntry): CoachFeedbackSummary[] {
  return (entry.feedback as CoachFeedbackSummary[] | undefined) ?? [];
}

export function isForbidden(error: unknown): boolean {
  return error instanceof ApiError && error.status === 403;
}

export function playerDisplayName(summary: CoachPlayerSummary | null, fallbackId: string): string {
  if (!summary) return fallbackId;
  return summary.name || summary.full_name || fallbackId;
}

export function sessionTitle(entry: CoachSessionEntry): string {
  return entry.session?.title_override ?? entry.offering?.name ?? 'Session';
}

export function sessionTime(entry: CoachSessionEntry, timezone: string): string {
  const startsAt = entry.session?.starts_at;
  if (!startsAt) return '';
  return formatTimeRange(startsAt, entry.session?.ends_at ?? startsAt, timezone);
}

export function directionsUrl(venueName: string | undefined, fallback: string): string {
  const query = encodeURIComponent(venueName || fallback);
  return `https://www.google.com/maps/search/?api=1&query=${query}`;
}

export type FeedbackStatus = 'none' | 'draft' | 'shared';

export function feedbackStatus(entries: CoachFeedbackSummary[]): FeedbackStatus {
  if (entries.some((entry) => entry.visibility === 'shared')) return 'shared';
  if (entries.length > 0) return 'draft';
  return 'none';
}

export const FEEDBACK_STATUS_LABEL: Record<FeedbackStatus, string> = {
  none: 'No feedback',
  draft: 'Draft',
  shared: 'Shared',
};

export const FEEDBACK_STATUS_VARIANT: Record<FeedbackStatus, 'outline' | 'warning' | 'success'> = {
  none: 'outline',
  draft: 'warning',
  shared: 'success',
};
