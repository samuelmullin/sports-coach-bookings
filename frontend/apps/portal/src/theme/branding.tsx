import { createContext, useContext, useEffect, type ReactNode } from 'react';
import {
  useSportsCoachBookingsWebPortalBrandingControllerShow,
  type SportsCoachBookingsWebPortalBrandingControllerShow200,
} from '@scb/api-client';
import { Splash, applyTheme, fontStack, platformTheme, type ThemeTokens } from '@scb/ui';

export type PortalBranding = SportsCoachBookingsWebPortalBrandingControllerShow200;

export interface BrandingValue {
  branding: PortalBranding;
  tenantName: string;
  tenantSlug: string;
  logoUrl?: string;
  faviconUrl?: string;
}

const BrandingContext = createContext<BrandingValue | null>(null);

export function brandingToTokens(branding: PortalBranding): ThemeTokens {
  const theme = branding.theme ?? {};
  return {
    ...platformTheme,
    primaryColor: theme.primary_color ?? platformTheme.primaryColor,
    primaryForegroundColor: platformTheme.primaryForegroundColor,
    secondaryColor: theme.secondary_color ?? platformTheme.secondaryColor,
    accentColor: theme.accent_color ?? platformTheme.accentColor,
    backgroundColor: theme.background_color ?? platformTheme.backgroundColor,
    textColor: theme.text_color ?? platformTheme.textColor,
    fontFamily: fontStack(theme.font_family),
  };
}

export function applyBrandingToDocument(branding: PortalBranding): void {
  if (typeof document === 'undefined') return;
  applyTheme(brandingToTokens(branding));
  const name = branding.tenant?.name;
  if (name) document.title = name;
  const favicon = branding.assets?.favicon_url;
  if (favicon) {
    let link = document.querySelector<HTMLLinkElement>('link[rel="icon"]');
    if (!link) {
      link = document.createElement('link');
      link.rel = 'icon';
      document.head.appendChild(link);
    }
    link.href = favicon;
  }
}

export function BrandingProvider({ children }: { children: ReactNode }) {
  const query = useSportsCoachBookingsWebPortalBrandingControllerShow();
  const branding = query.data?.data as PortalBranding | undefined;

  useEffect(() => {
    if (branding) applyBrandingToDocument(branding);
  }, [branding]);

  if (query.isLoading) {
    return <Splash label="Loading…" />;
  }

  if (!branding) {
    return <Splash label="This coaching business is unavailable." />;
  }

  const value: BrandingValue = {
    branding,
    tenantName: branding.tenant?.name ?? 'SportsCoachBookings',
    tenantSlug: branding.tenant?.slug ?? '',
    logoUrl: branding.assets?.logo_url ?? undefined,
    faviconUrl: branding.assets?.favicon_url ?? undefined,
  };

  return <BrandingContext.Provider value={value}>{children}</BrandingContext.Provider>;
}

export function useBranding(): BrandingValue {
  const context = useContext(BrandingContext);
  if (!context) {
    throw new Error('useBranding must be used within <BrandingProvider>');
  }
  return context;
}
