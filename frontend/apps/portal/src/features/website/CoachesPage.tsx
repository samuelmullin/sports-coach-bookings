import { Card, CardContent } from '@scb/ui';
import { MarketingPage } from './MarketingPage';
import { useWebsiteContent } from './useWebsiteContent';

export function CoachesPage() {
  const coaches = useWebsiteContent()?.coaches ?? [];
  return (
    <MarketingPage
      eyebrow="The team"
      title="Meet your coaches."
      intro="The people who lead your sessions and help every player grow."
    >
      <div className="grid gap-5 md:grid-cols-2">
        {coaches.map((coach, index) => (
          <Card key={`${coach.name}-${index}`} className="overflow-hidden">
            {coach.photo_url ? (
              <img
                src={coach.photo_url}
                alt={coach.name ?? ''}
                className="h-72 w-full object-cover"
              />
            ) : null}
            <CardContent className="space-y-2 pt-5">
              <h2 className="text-xl font-semibold">{coach.name}</h2>
              <p className="text-sm font-semibold uppercase tracking-wide text-primary">
                {coach.title}
              </p>
              <p className="leading-7 text-muted-foreground">{coach.bio}</p>
            </CardContent>
          </Card>
        ))}
      </div>
    </MarketingPage>
  );
}
