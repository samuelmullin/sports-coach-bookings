/**
 * Endpoints that are **not yet in the OpenAPI spec**.
 *
 * - `notification_preferences` (reminder timing): the settings WP does not
 *   expose reminder timing yet.
 * - `broadcasts/*`: owned by wp-17 (Notifications.Broadcasts), which is not
 *   built yet.
 *
 * These call the fetch mutator directly and are served by MSW in
 * `apps/admin/src/mocks.ts` (browser) and by handlers in tests. Swap for the
 * generated hooks once those work packages land.
 */
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { customFetch, type FetchResult } from '@scb/api-client';

async function fetchBody<T>(url: string, init?: RequestInit): Promise<T> {
  const result = await customFetch<FetchResult<T>>(url, init);
  return result.data;
}

function jsonInit(method: string, body: unknown): RequestInit {
  return {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  };
}

// ---------------------------------------------------------------------------
// Reminder timing (mock-only)
// ---------------------------------------------------------------------------
export interface NotificationPreferences {
  reminder_lead_hours: number;
  reminder_email: boolean;
  reminder_sms: boolean;
}

export const NOTIFICATION_PREFERENCES_KEY = ['/api/staff/notification_preferences'];

export function useNotificationPreferences() {
  return useQuery({
    queryKey: NOTIFICATION_PREFERENCES_KEY,
    queryFn: () => fetchBody<NotificationPreferences>('/api/staff/notification_preferences'),
  });
}

export function useUpdateNotificationPreferences() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (data: NotificationPreferences) =>
      fetchBody<NotificationPreferences>(
        '/api/staff/notification_preferences',
        jsonInit('PUT', data),
      ),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: NOTIFICATION_PREFERENCES_KEY }),
  });
}

// ---------------------------------------------------------------------------
// Broadcasts (wp-17, mock-only)
// ---------------------------------------------------------------------------
export type BroadcastCategory = 'operational' | 'marketing';
export type BroadcastStatus = 'draft' | 'scheduled' | 'sending' | 'sent';

export interface BroadcastSegment {
  venue_ids: string[];
  offering_ids: string[];
  household_ids: string[];
}

export interface Broadcast {
  id: string;
  subject: string;
  body_markdown: string;
  category: BroadcastCategory;
  status: BroadcastStatus;
  segment: BroadcastSegment;
  recipient_count: number;
  delivered_count: number;
  open_count: number;
  scheduled_at: string | null;
  sent_at: string | null;
  inserted_at: string;
}

export interface BroadcastInput {
  subject: string;
  body_markdown: string;
  category: BroadcastCategory;
  segment: BroadcastSegment;
  scheduled_at?: string | null;
}

export const BROADCASTS_KEY = ['/api/staff/broadcasts'];

export function useBroadcasts() {
  return useQuery({
    queryKey: BROADCASTS_KEY,
    queryFn: async () => (await fetchBody<{ data: Broadcast[] }>('/api/staff/broadcasts')).data,
  });
}

export function useRecipientCount(segment: BroadcastSegment, enabled = true) {
  return useQuery({
    queryKey: ['/api/staff/broadcasts/recipients', segment],
    queryFn: async () =>
      fetchBody<{ count: number }>(`/api/staff/broadcasts/recipients?${serializeSegment(segment)}`),
    enabled,
  });
}

export function useCreateBroadcast() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (data: BroadcastInput) =>
      fetchBody<Broadcast>('/api/staff/broadcasts', jsonInit('POST', data)),
    onSuccess: () => queryClient.invalidateQueries({ queryKey: BROADCASTS_KEY }),
  });
}

export function useSendTestBroadcast() {
  return useMutation({
    mutationFn: (data: BroadcastInput) =>
      fetchBody<{ sent: number }>('/api/staff/broadcasts/test', jsonInit('POST', data)),
  });
}

function serializeSegment(segment: BroadcastSegment): string {
  const params = new URLSearchParams();
  if (segment.venue_ids.length) params.set('venue_ids', segment.venue_ids.join(','));
  if (segment.offering_ids.length) params.set('offering_ids', segment.offering_ids.join(','));
  if (segment.household_ids.length) params.set('household_ids', segment.household_ids.join(','));
  return params.toString();
}
