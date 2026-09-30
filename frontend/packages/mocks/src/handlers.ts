import { HttpResponse, delay, http, type RequestHandler } from 'msw';

export type MockStaffRole = 'owner' | 'admin' | 'coach';

export interface MockBranding {
  assets: { favicon_url: string | null; logo_url: string | null };
  email_footer_text: string | null;
  social_links: Record<string, unknown>;
  tenant: { name: string; slug: string };
  theme: {
    accent_color: string;
    background_color: string;
    font_family: string;
    primary_color: string;
    secondary_color: string;
    text_color: string;
  };
}

export const mockBrandings: Record<string, MockBranding> = {
  demo: {
    assets: {
      favicon_url: 'https://cdn.example.com/demo/favicon.png',
      logo_url: 'https://cdn.example.com/demo/logo.svg',
    },
    email_footer_text: 'Sent by Demo Soccer Club',
    social_links: { instagram: 'https://instagram.com/demosoccer' },
    tenant: { name: 'Demo Soccer Club', slug: 'demo' },
    theme: {
      accent_color: '#f59e0b',
      background_color: '#f8fafc',
      font_family: 'Inter, sans-serif',
      primary_color: '#15803d',
      secondary_color: '#166534',
      text_color: '#0f172a',
    },
  },
  united: {
    assets: {
      favicon_url: 'https://cdn.example.com/united/favicon.png',
      logo_url: 'https://cdn.example.com/united/logo.svg',
    },
    email_footer_text: 'Sent by United Coaching',
    social_links: {},
    tenant: { name: 'United Coaching', slug: 'united' },
    theme: {
      accent_color: '#db2777',
      background_color: '#faf5ff',
      font_family: 'Georgia, serif',
      primary_color: '#7c3aed',
      secondary_color: '#4c1d95',
      text_color: '#1e1b4b',
    },
  },
};

interface MockStaffSession {
  signedIn: boolean;
  role: MockStaffRole;
  email: string;
  displayName: string;
  tenantSlug: string;
}

interface MockCustomerSession {
  signedIn: boolean;
  email: string;
  firstName: string;
  lastName: string;
  tenantSlug: string;
}

const defaultStaffSession: MockStaffSession = {
  signedIn: true,
  role: 'owner',
  email: 'owner@demo.test',
  displayName: 'Dana Owner',
  tenantSlug: 'demo',
};

const defaultCustomerSession: MockCustomerSession = {
  signedIn: false,
  email: 'parent@demo.test',
  firstName: 'Pat',
  lastName: 'Parent',
  tenantSlug: 'demo',
};

let staffSession: MockStaffSession = { ...defaultStaffSession };
let customerSession: MockCustomerSession = { ...defaultCustomerSession };
const takenSlugs = new Set(['demo', 'united', 'admin', 'www', 'api']);

export function setMockStaffSession(patch: Partial<MockStaffSession> = {}): void {
  staffSession = { ...staffSession, ...patch };
}

export function setMockCustomerSession(patch: Partial<MockCustomerSession> = {}): void {
  customerSession = { ...customerSession, ...patch };
}

export function resetMockSessions(): void {
  staffSession = { ...defaultStaffSession };
  customerSession = { ...defaultCustomerSession };
}

export function setMockBranding(slug: string, branding: MockBranding): void {
  mockBrandings[slug] = branding;
}

function brandingForHost(host: string): MockBranding {
  const slug = host.split('.')[0] ?? 'demo';
  return mockBrandings[slug] ?? mockBrandings.demo;
}

function errorEnvelope(code: string, message: string, fields?: unknown) {
  return { error: { code, message, details: fields ? { fields } : {} } };
}

function staffMembership() {
  const branding = mockBrandings[staffSession.tenantSlug] ?? mockBrandings.demo;
  return {
    id: 'membership-1',
    role: staffSession.role,
    status: 'active',
    display_name: staffSession.displayName,
    tenant_id: `tenant-${staffSession.tenantSlug}`,
    staff_user_id: 'staff-user-1',
    tenant: {
      id: `tenant-${staffSession.tenantSlug}`,
      name: branding.tenant.name,
      slug: branding.tenant.slug,
      status: 'active',
      currency: 'CAD',
      timezone: 'America/Toronto',
      contact_email: `hello@${branding.tenant.slug}.test`,
    },
    staff_user: {
      id: 'staff-user-1',
      email: staffSession.email,
      confirmed: true,
      confirmed_at: '2026-01-01T00:00:00Z',
      inserted_at: '2026-01-01T00:00:00Z',
    },
  };
}

export function getMockHandlers(options: { delayMs?: number } = {}): RequestHandler[] {
  const wait = options.delayMs ?? 0;

  return [
    http.get('/api/portal/branding', async ({ request }) => {
      if (wait) await delay(wait);
      const host = new URL(request.url).hostname;
      const branding = brandingForHost(host);
      return HttpResponse.json(branding);
    }),

    http.get('/api/staff/settings', () => {
      const branding = mockBrandings[staffSession.tenantSlug] ?? mockBrandings.demo;
      return HttpResponse.json({
        currency_locked: false,
        tenant: {
          id: `tenant-${branding.tenant.slug}`,
          name: branding.tenant.name,
          slug: branding.tenant.slug,
          status: 'active',
          currency: 'CAD',
          timezone: 'America/Toronto',
          contact_email: `hello@${branding.tenant.slug}.test`,
        },
      });
    }),

    http.get('/api/platform/me', () => {
      if (!staffSession.signedIn) {
        return HttpResponse.json(errorEnvelope('unauthorized', 'Not authenticated'), {
          status: 401,
        });
      }
      return HttpResponse.json({
        staff_user: {
          id: 'staff-user-1',
          email: staffSession.email,
          confirmed: true,
        },
        memberships: [staffMembership()],
      });
    }),

    http.post('/api/platform/session', async ({ request }) => {
      const body = (await request.json().catch(() => ({}))) as {
        email?: string;
      };
      staffSession = {
        ...staffSession,
        signedIn: true,
        email: body.email ?? staffSession.email,
      };
      return HttpResponse.json(
        {
          staff_user: {
            id: 'staff-user-1',
            email: staffSession.email,
            confirmed: true,
          },
        },
        { status: 201 },
      );
    }),

    http.delete('/api/platform/session', () => {
      staffSession = { ...staffSession, signedIn: false };
      return new HttpResponse(null, { status: 204 });
    }),

    http.post('/api/platform/signup', async ({ request }) => {
      const body = (await request.json().catch(() => ({}))) as {
        name?: string;
        slug?: string;
        email?: string;
      };
      const slug = body.slug ?? 'new-club';
      takenSlugs.add(slug);
      staffSession = {
        ...staffSession,
        signedIn: true,
        role: 'owner',
        email: body.email ?? staffSession.email,
        tenantSlug: slug,
      };
      return HttpResponse.json(
        {
          tenant: {
            id: `tenant-${slug}`,
            name: body.name ?? 'New Club',
            slug,
            status: 'active',
          },
          staff_user: {
            id: 'staff-user-1',
            email: staffSession.email,
            confirmed: false,
          },
          membership: staffMembership(),
        },
        { status: 201 },
      );
    }),

    http.get('/api/platform/slug_available', ({ request }) => {
      const slug = new URL(request.url).searchParams.get('slug') ?? '';
      const available = slug.length > 0 && !takenSlugs.has(slug.toLowerCase());
      return HttpResponse.json({
        slug,
        available,
        reason: available ? null : 'Slug is already taken',
      });
    }),

    http.post('/api/platform/staff_users', () =>
      HttpResponse.json(
        {
          staff_user: {
            id: 'staff-user-1',
            email: staffSession.email,
            confirmed: false,
          },
        },
        { status: 201 },
      ),
    ),

    http.post('/api/platform/confirmation', () =>
      HttpResponse.json({
        staff_user: { id: 'staff-user-1', confirmed: true },
      }),
    ),

    http.post('/api/platform/confirmation/resend', () =>
      HttpResponse.json({ message: 'Confirmation sent' }, { status: 202 }),
    ),

    http.post('/api/platform/password_reset', () =>
      HttpResponse.json({ message: 'Reset sent' }, { status: 202 }),
    ),

    http.put('/api/platform/password_reset', () =>
      HttpResponse.json({ message: 'Password updated' }),
    ),

    http.get('/api/invites/:token', () =>
      HttpResponse.json({
        email: 'invitee@demo.test',
        expired: false,
        role: 'coach',
        tenant_name: 'Demo Soccer Club',
      }),
    ),

    http.post('/api/invites/:token/accept', () =>
      HttpResponse.json(
        {
          membership: staffMembership(),
          staff_user: { id: 'staff-user-1', email: 'invitee@demo.test' },
        },
        { status: 201 },
      ),
    ),

    http.get('/api/portal/account', () => {
      if (!customerSession.signedIn) {
        return HttpResponse.json(errorEnvelope('unauthorized', 'Not authenticated'), {
          status: 401,
        });
      }
      return HttpResponse.json({
        customer_user: {
          id: 'customer-user-1',
          email: customerSession.email,
          first_name: customerSession.firstName,
          last_name: customerSession.lastName,
          confirmed: true,
          active: true,
          tenant_id: `tenant-${customerSession.tenantSlug}`,
        },
      });
    }),

    http.post('/api/portal/session', async ({ request }) => {
      const body = (await request.json().catch(() => ({}))) as {
        email?: string;
      };
      customerSession = {
        ...customerSession,
        signedIn: true,
        email: body.email ?? customerSession.email,
      };
      return HttpResponse.json(
        {
          customer_user: {
            id: 'customer-user-1',
            email: customerSession.email,
            first_name: customerSession.firstName,
            last_name: customerSession.lastName,
            confirmed: true,
            active: true,
          },
        },
        { status: 201 },
      );
    }),

    http.delete('/api/portal/session', () => {
      customerSession = { ...customerSession, signedIn: false };
      return new HttpResponse(null, { status: 204 });
    }),

    http.post('/api/portal/registrations', () =>
      HttpResponse.json({ confirmation_token: 'mock-confirmation-token' }, { status: 201 }),
    ),

    http.post('/api/portal/confirmation', () =>
      HttpResponse.json({
        customer_user: {
          id: 'customer-user-1',
          email: customerSession.email,
          first_name: customerSession.firstName,
          last_name: customerSession.lastName,
          confirmed: true,
          active: true,
        },
      }),
    ),

    http.post('/api/portal/confirmation/resend', () =>
      HttpResponse.json({ message: 'Confirmation sent' }, { status: 202 }),
    ),

    http.post('/api/portal/password_reset', () =>
      HttpResponse.json({ message: 'Reset sent' }, { status: 202 }),
    ),

    http.put('/api/portal/password_reset', () =>
      HttpResponse.json({ message: 'Password updated' }),
    ),

    http.get('/api/portal/household_invites/:token', () =>
      HttpResponse.json({
        email: 'family@demo.test',
        expired: false,
        relationship: 'Parent',
        tenant_name: 'Demo Soccer Club',
      }),
    ),

    http.post('/api/portal/household_invites/:token/accept', () =>
      HttpResponse.json(
        {
          customer_user: {
            id: 'customer-user-2',
            email: 'family@demo.test',
            first_name: 'Alex',
            last_name: 'Family',
            confirmed: true,
            active: true,
          },
        },
        { status: 201 },
      ),
    ),
  ];
}
