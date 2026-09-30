import { useState } from 'react';
import { NavLink, Outlet } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { Avatar, AvatarFallback, Button, IconButton, cn } from '@scb/ui';
import { LogOut, Menu, X } from 'lucide-react';
import { useStaffAuth } from '../auth/staff-auth';
import { navForRole } from '../navigation';
import { TenantSwitcher } from '../components/TenantSwitcher';

export function AdminLayout() {
  const { t } = useTranslation();
  const { role, staffUser, signOut, membership } = useStaffAuth();
  const [mobileOpen, setMobileOpen] = useState(false);
  const items = navForRole(role);

  const initials =
    staffUser?.email?.slice(0, 2).toUpperCase() ??
    membership?.display_name?.slice(0, 2).toUpperCase() ??
    'SC';

  return (
    <div className="flex min-h-screen bg-background text-foreground">
      <aside
        className={cn(
          'fixed inset-y-0 left-0 z-30 w-60 border-r border-border bg-surface p-4 transition-transform lg:static lg:translate-x-0',
          mobileOpen ? 'translate-x-0' : '-translate-x-full',
        )}
        aria-label="Main navigation"
      >
        <div className="mb-6 flex items-center justify-between">
          <span className="text-sm font-semibold">{t('common.admin')}</span>
          <IconButton
            label={t('common.close')}
            className="lg:hidden"
            icon={<X className="h-4 w-4" aria-hidden="true" />}
            onClick={() => setMobileOpen(false)}
          />
        </div>
        <nav className="flex flex-col gap-1">
          {items.map((item) => (
            <NavLink
              key={item.to}
              to={item.to}
              end={item.to === '/'}
              onClick={() => setMobileOpen(false)}
              className={({ isActive }) =>
                cn(
                  'rounded-md px-3 py-2 text-sm font-medium hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                  isActive ? 'bg-primary text-primary-foreground' : 'text-foreground',
                )
              }
            >
              {t(item.labelKey)}
            </NavLink>
          ))}
        </nav>
      </aside>

      <div className="flex w-full flex-col">
        <header className="flex h-14 items-center justify-between gap-3 border-b border-border bg-surface px-4">
          <div className="flex items-center gap-2">
            <IconButton
              label="Open navigation"
              className="lg:hidden"
              icon={<Menu className="h-5 w-5" aria-hidden="true" />}
              onClick={() => setMobileOpen(true)}
            />
            <TenantSwitcher />
          </div>
          <div className="flex items-center gap-3">
            <span
              className="hidden text-sm text-muted-foreground sm:inline"
              data-testid="staff-role"
            >
              {role}
            </span>
            <Avatar>
              <AvatarFallback>{initials}</AvatarFallback>
            </Avatar>
            <Button variant="outline" size="sm" onClick={() => void signOut()}>
              <LogOut className="h-4 w-4" aria-hidden="true" />
              {t('common.signOut')}
            </Button>
          </div>
        </header>
        <main className="flex-1 p-4 lg:p-6">
          <Outlet />
        </main>
      </div>
    </div>
  );
}
