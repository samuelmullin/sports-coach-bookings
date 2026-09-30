import type { StaffRole } from './auth/staff-auth';

export interface NavItem {
  to: string;
  labelKey: string;
  roles: StaffRole[];
}

export const navItems: NavItem[] = [
  { to: '/', labelKey: 'nav.dashboard', roles: ['owner', 'admin'] },
  { to: '/schedule', labelKey: 'nav.schedule', roles: ['owner', 'admin'] },
  { to: '/my-sessions', labelKey: 'nav.sessions', roles: ['owner', 'admin', 'coach'] },
  { to: '/players', labelKey: 'nav.players', roles: ['owner', 'admin', 'coach'] },
  { to: '/customers', labelKey: 'nav.customers', roles: ['owner', 'admin'] },
  { to: '/orders', labelKey: 'nav.orders', roles: ['owner', 'admin'] },
  { to: '/catalog', labelKey: 'nav.catalog', roles: ['owner', 'admin'] },
  { to: '/policies', labelKey: 'nav.policies', roles: ['owner', 'admin'] },
  { to: '/waivers', labelKey: 'nav.waivers', roles: ['owner', 'admin'] },
  { to: '/inventory', labelKey: 'nav.inventory', roles: ['owner', 'admin'] },
  { to: '/messaging', labelKey: 'nav.messaging', roles: ['owner', 'admin'] },
  { to: '/team', labelKey: 'nav.team', roles: ['owner', 'admin'] },
  { to: '/feedback', labelKey: 'nav.feedback', roles: ['owner', 'admin', 'coach'] },
  { to: '/settings', labelKey: 'nav.settings', roles: ['owner', 'admin'] },
];

export function navForRole(role: StaffRole | undefined): NavItem[] {
  if (!role) return [];
  return navItems.filter((item) => item.roles.includes(role));
}
