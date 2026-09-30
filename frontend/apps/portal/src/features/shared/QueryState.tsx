import type { ReactNode } from 'react';
import { AlertCircle } from 'lucide-react';
import { Button, Skeleton } from '@scb/ui';

export function QueryState({
  loading,
  error,
  onRetry,
  children,
  skeletonRows = 3,
}: {
  loading?: boolean;
  error?: string;
  onRetry?: () => void;
  children: ReactNode;
  skeletonRows?: number;
}) {
  if (loading) {
    return (
      <div className="flex flex-col gap-2" aria-label="Loading" data-testid="query-loading">
        {Array.from({ length: skeletonRows }).map((_, index) => (
          <Skeleton key={index} className="h-16 w-full" />
        ))}
      </div>
    );
  }

  if (error) {
    return (
      <div className="flex flex-col items-center gap-3 rounded-lg border border-danger/40 bg-danger/5 p-6 text-center">
        <AlertCircle className="h-6 w-6 text-danger" aria-hidden="true" />
        <p className="text-sm text-foreground">{error}</p>
        {onRetry ? (
          <Button variant="outline" size="sm" onClick={onRetry}>
            Try again
          </Button>
        ) : null}
      </div>
    );
  }

  return <>{children}</>;
}
