import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';
import { Card, CardContent } from '@scb/ui';
import { PortalLogo } from './PortalLayout';

export function PortalAuthLayout({
  title,
  subtitle,
  children,
  footer,
}: {
  title: string;
  subtitle?: string;
  children: ReactNode;
  footer?: ReactNode;
}) {
  return (
    <div className="flex min-h-screen flex-col items-center justify-center bg-background p-4">
      <Link to="/" className="mb-6">
        <PortalLogo />
      </Link>
      <Card className="w-full max-w-md">
        <CardContent className="pt-6">
          <h1 className="text-xl font-semibold">{title}</h1>
          {subtitle ? (
            <p className="mt-1 mb-4 text-sm text-muted-foreground">{subtitle}</p>
          ) : (
            <div className="mb-4" />
          )}
          {children}
        </CardContent>
      </Card>
      {footer ? <div className="mt-4 text-sm">{footer}</div> : null}
    </div>
  );
}
