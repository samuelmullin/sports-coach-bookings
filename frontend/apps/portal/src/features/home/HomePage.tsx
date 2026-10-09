import { ArrowRight, Check } from 'lucide-react';
import { Link } from 'react-router-dom';
import { Button, Card, CardContent } from '@scb/ui';
import { useOfferings, type OfferingResponse } from '../../api/endpoints';
import { listItems } from '../shared/api-utils';
import { useBranding } from '../../theme/branding';
import { useWebsiteContent } from '../website/useWebsiteContent';
import { SiteLink } from '../website/SiteLink';

export function HomePage() {
  const { tenantName } = useBranding();
  const content = useWebsiteContent();
  const hero = content?.hero;
  const story = content?.story;
  const offerings = listItems<OfferingResponse>(useOfferings()).slice(0, 6);
  const testimonials = content?.testimonials?.slice(0, 3) ?? [];

  return (
    <div className="flex flex-col gap-16 pb-12 sm:gap-24">
      <section className="relative -mx-4 -mt-6 overflow-hidden bg-surface px-4 py-16 sm:rounded-b-[2.5rem] sm:px-10 sm:py-24">
        {hero?.image_url ? (
          <img
            src={hero.image_url}
            alt=""
            className="absolute inset-0 h-full w-full object-cover opacity-20"
          />
        ) : null}
        <div className="relative max-w-3xl">
          <p className="mb-4 text-sm font-semibold uppercase tracking-[0.2em] text-primary">
            {hero?.eyebrow ?? tenantName}
          </p>
          <h1 className="text-5xl font-bold tracking-tight sm:text-7xl">
            {hero?.title ?? 'Develop your game.'}
          </h1>
          <p className="mt-6 max-w-2xl text-lg leading-8 text-muted-foreground sm:text-xl">
            {hero?.body ?? 'Find the right coaching session and book online.'}
          </p>
          <div className="mt-8 flex flex-wrap gap-3">
            <SiteLink
              href={hero?.primary_cta_url ?? '/schedule'}
              className="rounded-md bg-primary px-5 py-3 font-semibold text-primary-foreground"
            >
              {hero?.primary_cta_label ?? 'Book a session'}
            </SiteLink>
            <SiteLink
              href={hero?.secondary_cta_url ?? '/about'}
              className="rounded-md border border-border bg-background px-5 py-3 font-semibold"
            >
              {hero?.secondary_cta_label ?? 'Our story'}
            </SiteLink>
          </div>
        </div>
      </section>

      {(content?.stats?.length ?? 0) > 0 ? (
        <dl className="grid grid-cols-2 gap-6 text-center sm:grid-cols-4">
          {content?.stats?.map((stat, index) => (
            <div key={`${stat.label}-${index}`}>
              <dt className="text-sm uppercase tracking-wide text-muted-foreground">
                {stat.label}
              </dt>
              <dd className="mt-2 text-3xl font-bold text-primary">{stat.value}</dd>
            </div>
          ))}
        </dl>
      ) : null}

      {story?.body ? (
        <section className="grid items-center gap-8 lg:grid-cols-2">
          {story.image_url ? (
            <img src={story.image_url} alt="" className="h-96 w-full rounded-3xl object-cover" />
          ) : (
            <div className="h-80 rounded-3xl bg-gradient-to-br from-primary to-secondary" />
          )}
          <div>
            <p className="text-sm font-semibold uppercase tracking-[0.18em] text-primary">
              {story.eyebrow ?? 'Our story'}
            </p>
            <h2 className="mt-3 text-3xl font-bold sm:text-4xl">{story.title}</h2>
            <p className="mt-5 whitespace-pre-line text-lg leading-8 text-muted-foreground">
              {story.body}
            </p>
            <Button asChild variant="outline" className="mt-6">
              <Link to="/about">Read our story</Link>
            </Button>
          </div>
        </section>
      ) : null}

      <section>
        <div className="mb-6 flex items-end justify-between gap-4">
          <div>
            <p className="text-sm font-semibold uppercase tracking-[0.18em] text-primary">
              Programs
            </p>
            <h2 className="mt-2 text-3xl font-bold">Training for every player.</h2>
          </div>
          <Link
            to="/schedule"
            className="hidden items-center gap-1 font-semibold text-primary sm:flex"
          >
            View schedule <ArrowRight className="h-4 w-4" />
          </Link>
        </div>
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {offerings.map((offering) => (
            <Card key={offering.id} className="group">
              <CardContent className="flex h-full flex-col pt-5">
                <p className="text-xs font-semibold uppercase tracking-wide text-primary">
                  {offering.duration_minutes} minutes · Ages {offering.min_age ?? 'all'}–
                  {offering.max_age ?? 'adult'}
                </p>
                <h3 className="mt-3 text-xl font-semibold">{offering.name}</h3>
                {offering.description ? (
                  <p className="mt-2 line-clamp-4 text-sm leading-6 text-muted-foreground">
                    {offering.description}
                  </p>
                ) : null}
                <Link
                  to={`/offerings/${offering.id}`}
                  className="mt-auto pt-5 font-semibold text-primary group-hover:underline"
                >
                  Explore program →
                </Link>
              </CardContent>
            </Card>
          ))}
        </div>
      </section>

      {(content?.features?.length ?? 0) > 0 ? (
        <section className="rounded-3xl bg-surface p-7 sm:p-10">
          <h2 className="text-3xl font-bold">Why families choose {tenantName}.</h2>
          <div className="mt-8 grid gap-7 sm:grid-cols-2">
            {content?.features?.map((feature, index) => (
              <div key={`${feature.title}-${index}`} className="flex gap-3">
                <Check className="mt-1 h-5 w-5 shrink-0 text-primary" />
                <div>
                  <h3 className="font-semibold">{feature.title}</h3>
                  <p className="mt-1 leading-7 text-muted-foreground">{feature.body}</p>
                </div>
              </div>
            ))}
          </div>
        </section>
      ) : null}

      {testimonials.length > 0 ? (
        <section>
          <p className="text-sm font-semibold uppercase tracking-[0.18em] text-primary">
            Testimonials
          </p>
          <h2 className="mt-2 text-3xl font-bold">What parents and players say.</h2>
          <div className="mt-6 grid gap-4 lg:grid-cols-3">
            {testimonials.map((item, index) => (
              <Card key={`${item.name}-${index}`}>
                <CardContent className="space-y-5 pt-6">
                  <blockquote className="text-lg leading-8">“{item.quote}”</blockquote>
                  <div>
                    <p className="font-semibold">{item.name}</p>
                    <p className="text-sm text-muted-foreground">{item.detail}</p>
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
          <Button asChild variant="outline" className="mt-6">
            <Link to="/testimonials">Read more stories</Link>
          </Button>
        </section>
      ) : null}

      <section className="rounded-3xl bg-primary px-7 py-12 text-primary-foreground sm:px-12">
        <h2 className="text-3xl font-bold">Ready to train with purpose?</h2>
        <p className="mt-3 max-w-2xl text-primary-foreground/80">
          Find a session that fits your player and reserve your place online.
        </p>
        <Button asChild variant="secondary" className="mt-6">
          <Link to="/schedule">Book a session</Link>
        </Button>
      </section>
    </div>
  );
}
