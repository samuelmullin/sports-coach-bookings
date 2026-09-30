import { useState } from 'react';
import { NavLink, Outlet } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { cn } from '@scb/ui';
import { Menu, X } from 'lucide-react';
import { IconButton } from '@scb/ui';
import { useBranding } from '../theme/branding';
import { useCustomerAuth } from '../auth/customer-auth';
import { GuestCartMerge } from '../features/cart/GuestCartMerge';
import { CartIconButton } from '../features/cart/CartIconButton';
import { ReservationBanner } from '../features/reservations/ReservationBanner';

export function PortalLogo() {
  const { logoUrl, tenantName } = useBranding();
  if (logoUrl) {
    return <img src={logoUrl} alt={tenantName} className="h-8 w-auto" data-testid="tenant-logo" />;
  }
  return (
    <span className="text-base font-semibold text-primary" data-testid="tenant-name">
      {tenantName}
    </span>
  );
}

export function PortalLayout() {
  const { t } = useTranslation();
  const { status, signOut } = useCustomerAuth();
  const [mobileOpen, setMobileOpen] = useState(false);
  const authenticated = status === 'authenticated';

  const links = [
    { to: '/', label: t('nav.home') },
    { to: '/schedule', label: t('nav.schedule') },
    { to: '/packages', label: t('nav.packages') },
    { to: '/shop', label: t('nav.shop') },
    ...(authenticated
      ? [
          { to: '/bookings', label: t('nav.bookings') },
          { to: '/players', label: t('nav.players') },
          { to: '/credits', label: t('nav.credits') },
          { to: '/orders', label: t('nav.orders') },
          { to: '/pickups', label: t('nav.pickups') },
          { to: '/household', label: t('nav.household') },
          { to: '/account', label: t('nav.account') },
        ]
      : []),
  ];

  return (
    <div className="flex min-h-screen flex-col bg-background text-foreground">
      <header className="sticky top-0 z-30 border-b border-border bg-surface">
        <div className="mx-auto flex h-14 w-full max-w-5xl items-center justify-between gap-3 px-4">
          <NavLink to="/" aria-label={t('nav.home')}>
            <PortalLogo />
          </NavLink>
          <nav className="hidden items-center gap-1 md:flex md:flex-wrap" aria-label="Main">
            {links.map((link) => (
              <NavLink
                key={link.to}
                to={link.to}
                end={link.to === '/'}
                className={({ isActive }) =>
                  cn(
                    'rounded-md px-3 py-2 text-sm font-medium hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                    isActive && 'text-primary',
                  )
                }
              >
                {link.label}
              </NavLink>
            ))}
          </nav>
          <div className="hidden items-center gap-2 md:flex">
            {authenticated ? (
              <button
                type="button"
                onClick={() => void signOut()}
                className="text-sm text-muted-foreground hover:text-foreground"
              >
                {t('common.signOut')}
              </button>
            ) : (
              <>
                <NavLink
                  to="/login"
                  className="text-sm font-medium text-foreground hover:text-primary"
                >
                  {t('common.signIn')}
                </NavLink>
                <NavLink
                  to="/register"
                  className="rounded-md bg-primary px-3 py-2 text-sm font-medium text-primary-foreground"
                >
                  {t('common.register')}
                </NavLink>
              </>
            )}
          </div>
          <div className="flex items-center gap-1">
            <CartIconButton />
            <IconButton
              label={t('common.menu')}
              className="md:hidden"
              icon={<Menu className="h-5 w-5" aria-hidden="true" />}
              onClick={() => setMobileOpen(true)}
            />
          </div>
        </div>
        {mobileOpen ? (
          <div className="border-t border-border bg-surface md:hidden">
            <div className="flex items-center justify-between px-4 py-2">
              <span className="text-sm font-medium">{t('common.menu')}</span>
              <IconButton
                label={t('common.close')}
                icon={<X className="h-4 w-4" aria-hidden="true" />}
                onClick={() => setMobileOpen(false)}
              />
            </div>
            <nav className="flex flex-col px-2 pb-3" aria-label="Mobile">
              {links.map((link) => (
                <NavLink
                  key={link.to}
                  to={link.to}
                  end={link.to === '/'}
                  onClick={() => setMobileOpen(false)}
                  className={({ isActive }) =>
                    cn(
                      'rounded-md px-3 py-2 text-sm font-medium',
                      isActive ? 'bg-muted text-primary' : 'hover:bg-muted',
                    )
                  }
                >
                  {link.label}
                </NavLink>
              ))}
              {!authenticated ? (
                <NavLink
                  to="/login"
                  onClick={() => setMobileOpen(false)}
                  className="rounded-md px-3 py-2 text-sm font-medium hover:bg-muted"
                >
                  {t('common.signIn')}
                </NavLink>
              ) : (
                <button
                  type="button"
                  onClick={() => void signOut()}
                  className="rounded-md px-3 py-2 text-left text-sm font-medium hover:bg-muted"
                >
                  {t('common.signOut')}
                </button>
              )}
            </nav>
          </div>
        ) : null}
      </header>

      <GuestCartMerge />
      <ReservationBanner />

      <main className="mx-auto w-full max-w-5xl flex-1 px-4 py-6">
        <Outlet />
      </main>

      <footer className="border-t border-border bg-surface">
        <div className="mx-auto w-full max-w-5xl px-4 py-4 text-xs text-muted-foreground">
          {t('common.appName')}
        </div>
      </footer>
    </div>
  );
}
