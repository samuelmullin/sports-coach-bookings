import type { ReactNode } from 'react';

export function MarketingPage({
  eyebrow,
  title,
  intro,
  children,
}: {
  eyebrow?: string;
  title: string;
  intro?: string;
  children: ReactNode;
}) {
  return (
    <div className="flex flex-col gap-10 py-6 sm:py-10">
      <header className="max-w-3xl">
        {eyebrow ? (
          <p className="mb-3 text-sm font-semibold uppercase tracking-[0.18em] text-primary">
            {eyebrow}
          </p>
        ) : null}
        <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">{title}</h1>
        {intro ? <p className="mt-4 text-lg leading-8 text-muted-foreground">{intro}</p> : null}
      </header>
      {children}
    </div>
  );
}
