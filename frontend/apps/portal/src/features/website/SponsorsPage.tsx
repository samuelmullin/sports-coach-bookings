import { Card, CardContent } from '@scb/ui';
import { MarketingPage } from './MarketingPage';
import { SiteLink } from './SiteLink';
import { useWebsiteContent } from './useWebsiteContent';

export function SponsorsPage() {
  const sponsors = useWebsiteContent()?.sponsors ?? [];
  return (
    <MarketingPage
      eyebrow="Community"
      title="Sponsors & supporters."
      intro="The people and businesses who help make coaching more accessible."
    >
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
        {sponsors.map((item, index) => (
          <Card key={`${item.name}-${index}`}>
            <CardContent className="flex h-full flex-col items-center gap-4 pt-5 text-center">
              {item.logo_url ? (
                <img
                  src={item.logo_url}
                  alt={item.name ?? ''}
                  className="h-24 max-w-full object-contain"
                />
              ) : null}
              <h2 className="font-semibold">{item.name}</h2>
              <p className="text-sm text-muted-foreground">{item.description}</p>
              {item.url ? (
                <SiteLink
                  href={item.url}
                  className="text-sm font-medium text-primary hover:underline"
                >
                  Visit website
                </SiteLink>
              ) : null}
            </CardContent>
          </Card>
        ))}
      </div>
    </MarketingPage>
  );
}
