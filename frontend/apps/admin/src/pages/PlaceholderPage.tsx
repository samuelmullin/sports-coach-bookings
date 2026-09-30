import { EmptyState } from '@scb/ui';
import { Inbox } from 'lucide-react';

export function PlaceholderPage({ title }: { title: string }) {
  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-xl font-semibold">{title}</h1>
      <EmptyState
        icon={<Inbox className="h-8 w-8" />}
        title={`${title} is coming soon`}
        description="This screen is built by a feature work package."
      />
    </div>
  );
}
