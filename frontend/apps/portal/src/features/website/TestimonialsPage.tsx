import { Card, CardContent } from '@scb/ui';
import { MarketingPage } from './MarketingPage';
import { useWebsiteContent } from './useWebsiteContent';

export function TestimonialsPage() {
  const testimonials = useWebsiteContent()?.testimonials ?? [];
  return (
    <MarketingPage eyebrow="From the community" title="What families say.">
      <div className="columns-1 gap-4 md:columns-2 lg:columns-3">
        {testimonials.map((item, index) => (
          <Card key={`${item.name}-${index}`} className="mb-4 break-inside-avoid">
            <CardContent className="space-y-4 pt-5">
              <blockquote className="leading-7">“{item.quote}”</blockquote>
              <div>
                <p className="font-semibold">{item.name}</p>
                <p className="text-sm text-muted-foreground">{item.detail}</p>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    </MarketingPage>
  );
}
