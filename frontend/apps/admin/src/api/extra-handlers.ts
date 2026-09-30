/** MSW handlers for the non-spec endpoints in `extras.ts`. */
import { HttpResponse, delay, http, type RequestHandler } from 'msw';
import type { Broadcast, BroadcastInput, NotificationPreferences } from './extras';

export const notificationPreferences: NotificationPreferences = {
  reminder_lead_hours: 24,
  reminder_email: true,
  reminder_sms: false,
};

export const broadcastStore: Broadcast[] = [
  {
    id: 'bcast-1',
    subject: 'Summer camp registration open',
    body_markdown: '# Summer camp\n\nRegistration is now open!',
    category: 'marketing',
    status: 'sent',
    segment: { venue_ids: [], offering_ids: [], household_ids: [] },
    recipient_count: 128,
    delivered_count: 126,
    open_count: 74,
    scheduled_at: null,
    sent_at: '2026-05-01T14:00:00Z',
    inserted_at: '2026-05-01T13:00:00Z',
  },
];

function countRecipients(segment: {
  venue_ids?: string[];
  offering_ids?: string[];
  household_ids?: string[];
}): number {
  const base = 42;
  const explicit = segment.household_ids?.length ?? 0;
  const offering = (segment.offering_ids?.length ?? 0) * 7;
  const venue = (segment.venue_ids?.length ?? 0) * 11;
  return base + explicit + offering + venue;
}

// ---------------------------------------------------------------------------
// Coach API (wp-15): deterministic fixtures so the coach flow is usable on
// mocks. The generated mocks return random faker data and empty player
// summaries, so these override them in the browser worker.
// ---------------------------------------------------------------------------
function daysFromNow(days: number, hour: number, minute = 0): string {
  const date = new Date();
  date.setDate(date.getDate() + days);
  date.setHours(hour, minute, 0, 0);
  return date.toISOString();
}

const COACH_ID = 'membership-1';

function coachPlayerSummary(id: string) {
  if (id === 'player-2') {
    return {
      id: 'player-2',
      name: 'Liam Keeper',
      full_name: 'Liam Keeper',
      age: 11,
      preferred_positions: ['GK'],
      has_medical_info: false,
      emergency_contact: null,
    };
  }
  return {
    id: 'player-1',
    name: 'Ava Striker',
    full_name: 'Ava Striker',
    age: 12,
    preferred_positions: ['ST', 'W'],
    has_medical_info: true,
    emergency_contact: { name: 'Priya Striker', relationship: 'Mother', phone: '+1-416-555-0101' },
  };
}

function coachSessionFixtures() {
  return [
    {
      session: {
        id: 'session-today',
        offering_id: 'offering-1',
        venue_id: 'venue-1',
        starts_at: daysFromNow(0, 18),
        ends_at: daysFromNow(0, 19),
        capacity: 8,
        booked_count: 2,
        seats_left: 6,
        status: 'scheduled',
        visibility: 'public',
        title_override: null,
        series_id: null,
      },
      offering: { id: 'offering-1', name: 'Group Clinic', duration_minutes: 60, format: 'group' },
      venue: { id: 'venue-1', name: 'Main Dome', timezone: 'America/Toronto' },
      seats_left: 6,
      bookable: true,
    },
    {
      session: {
        id: 'session-upcoming',
        offering_id: 'offering-2',
        venue_id: 'venue-2',
        starts_at: daysFromNow(3, 17, 30),
        ends_at: daysFromNow(3, 18, 30),
        capacity: 1,
        booked_count: 1,
        seats_left: 0,
        status: 'scheduled',
        visibility: 'public',
        title_override: 'Private 1:1',
        series_id: null,
      },
      offering: {
        id: 'offering-2',
        name: 'Private Training',
        duration_minutes: 60,
        format: 'private',
      },
      venue: { id: 'venue-2', name: 'North Field', timezone: 'America/Toronto' },
      seats_left: 0,
      bookable: false,
    },
    {
      session: {
        id: 'session-past',
        offering_id: 'offering-1',
        venue_id: 'venue-1',
        starts_at: daysFromNow(-5, 18),
        ends_at: daysFromNow(-5, 19),
        capacity: 8,
        booked_count: 2,
        seats_left: 6,
        status: 'completed',
        visibility: 'public',
        title_override: null,
        series_id: null,
      },
      offering: { id: 'offering-1', name: 'Group Clinic', duration_minutes: 60, format: 'group' },
      venue: { id: 'venue-1', name: 'Main Dome', timezone: 'America/Toronto' },
      seats_left: 6,
      bookable: false,
    },
  ];
}

function coachRosterFixtures(sessionId: string) {
  return [
    {
      booking_id: 'booking-1',
      player_id: 'player-1',
      player: coachPlayerSummary('player-1'),
      status: 'attended',
      payment_method: 'credits',
      credits_used: 1,
      hold_expires_at: null,
      feedback: [
        {
          id: 'feedback-1',
          session_id: sessionId,
          player_id: 'player-1',
          coach_id: COACH_ID,
          visibility: 'shared',
          shared_at: daysFromNow(-5, 20),
          edited_at: null,
        },
      ],
    },
    {
      booking_id: 'booking-2',
      player_id: 'player-2',
      player: coachPlayerSummary('player-2'),
      status: 'confirmed',
      payment_method: 'card',
      credits_used: 0,
      hold_expires_at: null,
      feedback: [],
    },
  ];
}

function coachFeedbackFixtures() {
  return [
    {
      id: 'feedback-1',
      session_id: 'session-past',
      player_id: 'player-1',
      coach_id: COACH_ID,
      body: '**Great movement** off the ball today. Keep scanning before receiving.',
      skill_ratings: { first_touch: 4, passing: 3 },
      focus_next: 'Weak-foot finishing',
      visibility: 'shared',
      shared_at: daysFromNow(-5, 20),
      edited_at: null,
      inserted_at: daysFromNow(-5, 20),
      updated_at: daysFromNow(-5, 20),
    },
    {
      id: 'feedback-2',
      session_id: 'session-today',
      player_id: 'player-2',
      coach_id: COACH_ID,
      body: 'Working on distribution under pressure.',
      skill_ratings: { first_touch: 3 },
      focus_next: 'Quick distribution',
      visibility: 'internal',
      shared_at: null,
      edited_at: null,
      inserted_at: daysFromNow(-1, 9),
      updated_at: daysFromNow(-1, 9),
    },
  ];
}

function coachPlayerDetailFixture(playerId: string) {
  return {
    player: {
      ...coachPlayerSummary(playerId),
      first_name: playerId === 'player-2' ? 'Liam' : 'Ava',
      last_name: playerId === 'player-2' ? 'Keeper' : 'Striker',
      preferred_name: null,
      date_of_birth: '2014-03-02',
      active: true,
      profile: {
        home_club: 'Demo FC',
        team: 'U12',
        preferred_positions: playerId === 'player-2' ? ['GK'] : ['ST', 'W'],
        dominant_foot: 'right',
        goals: 'Play rep soccer next season',
        interests: 'Music, basketball',
        notes_from_family: 'Sensitive to heat — bring water.',
      },
      emergency_contacts:
        playerId === 'player-2'
          ? [
              {
                id: 'ec-2',
                name: 'Sam Keeper',
                relationship: 'Father',
                phone: '+1-416-555-0102',
                alt_phone: null,
                priority: 1,
              },
            ]
          : [
              {
                id: 'ec-1',
                name: 'Priya Striker',
                relationship: 'Mother',
                phone: '+1-416-555-0101',
                alt_phone: null,
                priority: 1,
              },
            ],
      authorized_pickups: [
        {
          id: 'ap-1',
          name: 'Jordan Aunt',
          relationship: 'Aunt',
          phone: '+1-416-555-0103',
          notes: 'Only on Fridays',
        },
      ],
    },
    feedback:
      playerId === 'player-2'
        ? coachFeedbackFixtures().filter((item) => item.player_id === 'player-2')
        : coachFeedbackFixtures().filter((item) => item.player_id === 'player-1'),
  };
}

const COACH_SKILL_TAGS = [
  { id: 'tag-1', name: 'First touch', slug: 'first_touch', position: 0, active: true },
  { id: 'tag-2', name: 'Passing', slug: 'passing', position: 1, active: true },
  { id: 'tag-3', name: 'Finishing', slug: 'finishing', position: 2, active: true },
  { id: 'tag-4', name: 'Positioning', slug: 'positioning', position: 3, active: true },
];

function getCoachMockHandlers(): RequestHandler[] {
  return [
    http.get('/api/staff/coach/sessions', () =>
      HttpResponse.json({ data: coachSessionFixtures(), next_cursor: null }),
    ),
    http.get('/api/staff/coach/sessions/:sessionId/roster', ({ params }) =>
      HttpResponse.json({ data: coachRosterFixtures(String(params.sessionId)) }),
    ),
    http.get('/api/staff/coach/players/:playerId', ({ params }) =>
      HttpResponse.json(coachPlayerDetailFixture(String(params.playerId))),
    ),
    http.post('/api/staff/coach/sessions/:sessionId/attendance', async ({ request }) => {
      const payload = (await request.json().catch(() => ({ attendance: [] }))) as {
        attendance?: { booking_id?: string; status?: string }[];
      };
      return HttpResponse.json({
        data: (payload.attendance ?? []).map((entry) => ({
          booking_id: entry.booking_id ?? null,
          status: entry.status ?? null,
          ok: true,
          error: null,
        })),
      });
    }),
    http.get('/api/staff/feedback/skill_tags', () => HttpResponse.json({ data: COACH_SKILL_TAGS })),
    http.get('/api/staff/feedback', () => {
      const data = coachFeedbackFixtures().map((item) => ({ ...item }));
      return HttpResponse.json({ data, next_cursor: null });
    }),
    http.post('/api/staff/feedback', async ({ request }) => {
      const payload = (await request.json().catch(() => ({}))) as Record<string, unknown>;
      const shared = payload.visibility === 'shared';
      return HttpResponse.json(
        {
          ...payload,
          id: 'feedback-new',
          coach_id: COACH_ID,
          visibility: shared ? 'shared' : 'internal',
          shared_at: shared ? new Date().toISOString() : null,
          edited_at: null,
          inserted_at: new Date().toISOString(),
          updated_at: new Date().toISOString(),
        },
        { status: 201 },
      );
    }),
    http.patch('/api/staff/feedback/:id', async ({ request, params }) => {
      const payload = (await request.json().catch(() => ({}))) as Record<string, unknown>;
      const existing = coachFeedbackFixtures().find((item) => item.id === params.id);
      return HttpResponse.json({
        ...(existing ?? coachFeedbackFixtures()[0]),
        ...payload,
        id: String(params.id),
        edited_at: new Date().toISOString(),
      });
    }),
    http.post('/api/staff/feedback/:id/share', ({ params }) => {
      const existing = coachFeedbackFixtures().find((item) => item.id === params.id);
      return HttpResponse.json({
        ...(existing ?? coachFeedbackFixtures()[0]),
        id: String(params.id),
        visibility: 'shared',
        shared_at: new Date().toISOString(),
      });
    }),
    http.get('/api/staff/feedback/:id/revisions', () => HttpResponse.json({ data: [] })),
  ];
}

export function getExtraMockHandlers(): RequestHandler[] {
  return [
    http.get('/api/staff/notification_preferences', () =>
      HttpResponse.json(notificationPreferences),
    ),
    http.put('/api/staff/notification_preferences', async ({ request }) => {
      const patch = (await request.json()) as Partial<NotificationPreferences>;
      Object.assign(notificationPreferences, patch);
      return HttpResponse.json(notificationPreferences);
    }),

    http.get('/api/staff/broadcasts', async () => {
      await delay(50);
      return HttpResponse.json({ data: broadcastStore });
    }),
    http.get('/api/staff/broadcasts/recipients', ({ request }) => {
      const url = new URL(request.url);
      const count = countRecipients({
        venue_ids: url.searchParams.get('venue_ids')?.split(',').filter(Boolean),
        offering_ids: url.searchParams.get('offering_ids')?.split(',').filter(Boolean),
        household_ids: url.searchParams.get('household_ids')?.split(',').filter(Boolean),
      });
      return HttpResponse.json({ count });
    }),
    http.post('/api/staff/broadcasts', async ({ request }) => {
      const input = (await request.json()) as BroadcastInput;
      const scheduled = Boolean(input.scheduled_at);
      const broadcast: Broadcast = {
        id: `bcast-${broadcastStore.length + 1}`,
        subject: input.subject,
        body_markdown: input.body_markdown,
        category: input.category,
        status: scheduled ? 'scheduled' : 'sending',
        segment: input.segment,
        recipient_count: countRecipients(input.segment),
        delivered_count: 0,
        open_count: 0,
        scheduled_at: input.scheduled_at ?? null,
        sent_at: null,
        inserted_at: new Date().toISOString(),
      };
      broadcastStore.unshift(broadcast);
      return HttpResponse.json(broadcast, { status: 201 });
    }),
    http.post('/api/staff/broadcasts/test', async ({ request }) => {
      const input = (await request.json()) as BroadcastInput;
      if (input.subject.trim().toLowerCase() === 'fail') {
        return HttpResponse.json(
          { error: { code: 'send_failed', message: 'Test send failed' } },
          { status: 422 },
        );
      }
      return HttpResponse.json({ sent: 1 });
    }),

    ...getCoachMockHandlers(),
  ];
}
