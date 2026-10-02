import { Skeleton } from './Skeleton';

/** Suspense fallback shown while a lazily loaded route chunk downloads. */
export function RouteFallback() {
  return (
    <div role="status" aria-live="polite" aria-busy="true" className="flex flex-col gap-4 p-4">
      <span className="sr-only">Loading…</span>
      <Skeleton className="h-8 w-1/3" />
      <Skeleton className="h-40 w-full" />
    </div>
  );
}
