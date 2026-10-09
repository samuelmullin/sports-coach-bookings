import { Suspense, useState } from 'react';
import { NavLink, Outlet, useLocation } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { cn } from '@scb/ui';
import { ChevronDown, Menu } from 'lucide-react';
import {
  Drawer,
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
  IconButton,
  RouteFallback,
} from '@scb/ui';
import { useBranding } from '../theme/branding';
import { useCustomerAuth } from '../auth/customer-auth';
import { GuestCartMerge } from '../features/cart/GuestCartMerge';
import { CartIconButton } from '../features/cart/CartIconButton';
import { ReservationBanner } from '../features/reservations/ReservationBanner';
import { useWebsiteContent } from '../features/website/useWebsiteContent';

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
  const { pathname } = useLocation();
  const website = useWebsiteContent();
  const [mobileOpen, setMobileOpen] = useState(false);
  const authenticated = status === 'authenticated';

  const primaryLinks = [
    { to: '/', label: t('nav.home') },
    { to: '/schedule', label: 'Programs' },
    { to: '/packages', label: t('nav.packages') },
    { to: '/shop', label: t('nav.shop') },
    { to: '/about', label: 'About' },
    ...(authenticated
      ? [
          { to: '/bookings', label: t('nav.bookings') },
          { to: '/players', label: t('nav.players') },
          { to: '/credits', label: t('nav.credits') },
        ]
      : []),
  ];
  const marketingLinks = [
    { to: '/coaches', label: 'Coaches' },
    { to: '/testimonials', label: 'Testimonials' },
    { to: '/gallery', label: 'Gallery' },
    { to: '/sponsors', label: 'Sponsors' },
    { to: '/faq', label: 'FAQ' },
    { to: '/contact', label: 'Contact' },
  ];
  // Less-used destinations live in a menu so the header never wraps.
  const accountLinks = authenticated
    ? [
        { to: '/orders', label: t('nav.orders') },
        { to: '/private-session-requests', label: t('nav.privateRequests') },
        { to: '/pickups', label: t('nav.pickups') },
        { to: '/household', label: t('nav.household') },
        { to: '/account', label: t('nav.account') },
      ]
    : [];
  const links = [...primaryLinks, ...marketingLinks, ...accountLinks];

  return (
    <div className="flex min-h-screen flex-col bg-background text-foreground">
      <header className="sticky top-0 z-30 border-b border-border bg-surface">
        {website?.announcement ? (
          <div className="bg-primary px-4 py-2 text-center text-sm font-medium text-primary-foreground">
            {website.announcement}
          </div>
        ) : null}
        <div className="mx-auto flex h-16 w-full max-w-7xl items-center justify-between gap-3 px-4">
          <NavLink to="/" aria-label={t('nav.home')}>
            <PortalLogo />
          </NavLink>
          <nav className="hidden items-center gap-1 lg:flex" aria-label="Main">
            {primaryLinks.map((link) => (
              <NavLink
                key={link.to}
                to={link.to}
                end={link.to === '/'}
                className={({ isActive }) =>
                  cn(
                    'whitespace-nowrap rounded-md px-3 py-2 text-sm font-medium hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                    isActive && 'text-primary',
                  )
                }
              >
                {link.label}
              </NavLink>
            ))}
            <DropdownMenu>
              <DropdownMenuTrigger
                className={cn(
                  'flex items-center gap-1 whitespace-nowrap rounded-md px-3 py-2 text-sm font-medium hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                  marketingLinks.some((link) => pathname.startsWith(link.to)) && 'text-primary',
                )}
              >
                Explore <ChevronDown className="h-4 w-4" aria-hidden="true" />
              </DropdownMenuTrigger>
              <DropdownMenuContent>
                {marketingLinks.map((link) => (
                  <DropdownMenuItem key={link.to} asChild>
                    <NavLink to={link.to}>{link.label}</NavLink>
                  </DropdownMenuItem>
                ))}
              </DropdownMenuContent>
            </DropdownMenu>
            {accountLinks.length > 0 ? (
              <DropdownMenu>
                <DropdownMenuTrigger
                  className={cn(
                    'flex items-center gap-1 whitespace-nowrap rounded-md px-3 py-2 text-sm font-medium hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                    accountLinks.some((link) => pathname.startsWith(link.to)) && 'text-primary',
                  )}
                >
                  {t('nav.myAccount')}
                  <ChevronDown className="h-4 w-4" aria-hidden="true" />
                </DropdownMenuTrigger>
                <DropdownMenuContent>
                  {accountLinks.map((link) => (
                    <DropdownMenuItem key={link.to} asChild>
                      <NavLink to={link.to}>{link.label}</NavLink>
                    </DropdownMenuItem>
                  ))}
                </DropdownMenuContent>
              </DropdownMenu>
            ) : null}
          </nav>
          <div className="hidden items-center gap-2 lg:flex">
            {authenticated ? (
              <button
                type="button"
                onClick={() => void signOut()}
                className="whitespace-nowrap text-sm text-muted-foreground hover:text-foreground"
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
              className="lg:hidden"
              icon={<Menu className="h-5 w-5" aria-hidden="true" />}
              onClick={() => setMobileOpen(true)}
            />
          </div>
        </div>
        <Drawer
          open={mobileOpen}
          onOpenChange={setMobileOpen}
          title={t('common.menu')}
          side="right"
          className="lg:hidden"
          closeLabel={t('common.close')}
        >
          <nav className="flex flex-col" aria-label="Mobile">
            {links.map((link) => (
              <NavLink
                key={link.to}
                to={link.to}
                end={link.to === '/'}
                onClick={() => setMobileOpen(false)}
                className={({ isActive }) =>
                  cn(
                    'rounded-md px-3 py-2 text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                    isActive ? 'bg-muted text-foreground' : 'hover:bg-muted',
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
                className="rounded-md px-3 py-2 text-sm font-medium hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              >
                {t('common.signIn')}
              </NavLink>
            ) : (
              <button
                type="button"
                onClick={() => void signOut()}
                className="rounded-md px-3 py-2 text-left text-sm font-medium hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
              >
                {t('common.signOut')}
              </button>
            )}
          </nav>
        </Drawer>
      </header>

      <GuestCartMerge />
      <ReservationBanner />

      <main className="mx-auto w-full max-w-7xl flex-1 px-4 py-6">
        <Suspense fallback={<RouteFallback />}>
          <Outlet />
        </Suspense>
      </main>

      <footer className="border-t border-border bg-surface">
        <div className="mx-auto grid w-full max-w-7xl gap-8 px-4 py-10 sm:grid-cols-3">
          <div>
            <PortalLogo />
            <p className="mt-3 max-w-sm text-sm leading-6 text-muted-foreground">
              {website?.footer?.tagline ??
                'Private and small-group coaching for players who want to grow.'}
            </p>
          </div>
          <nav aria-label="Footer" className="grid grid-cols-2 gap-x-4 gap-y-2 text-sm">
            {marketingLinks.map((link) => (
              <NavLink key={link.to} to={link.to} className="hover:text-primary">
                {link.label}
              </NavLink>
            ))}
          </nav>
          <div className="space-y-2 text-sm text-muted-foreground">
            {website?.contact?.email ? (
              <a className="block hover:text-primary" href={`mailto:${website.contact.email}`}>
                {website.contact.email}
              </a>
            ) : null}
            {website?.contact?.phone ? (
              <a className="block hover:text-primary" href={`tel:${website.contact.phone}`}>
                {website.contact.phone}
              </a>
            ) : null}
            {website?.contact?.address ? <p>{website.contact.address}</p> : null}
          </div>
        </div>
        <div className="border-t border-border px-4 py-4 text-center text-xs text-muted-foreground">
          © {new Date().getFullYear()} {website?.seo?.title ?? t('common.appName')}
        </div>
      </footer>
    </div>
  );
}
