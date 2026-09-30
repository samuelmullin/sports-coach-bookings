import { cn } from '../lib/cn';

export interface SplashProps {
  label?: string;
  className?: string;
}

export function Splash({ label = 'Loading…', className }: SplashProps) {
  return (
    <div
      role="status"
      aria-live="polite"
      data-testid="scb-splash"
      className={cn(
        'flex min-h-screen w-full flex-col items-center justify-center gap-4 bg-neutral-100 text-neutral-500',
        className,
      )}
    >
      <div
        aria-hidden="true"
        className="h-8 w-8 animate-spin rounded-full border-2 border-neutral-300 border-t-neutral-600"
      />
      <span className="text-sm font-medium">{label}</span>
    </div>
  );
}
