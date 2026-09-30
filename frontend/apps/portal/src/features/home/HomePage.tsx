import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { ArrowRight } from 'lucide-react';
import { Button, Card, CardContent } from '@scb/ui';
import {
  useOfferings,
  usePackages,
  type OfferingResponse,
  type PackageResponse,
} from '../../api/endpoints';
import { listItems } from '../shared/api-utils';
import { Money } from '../shared/Money';
import { useBranding } from '../../theme/branding';

export function HomePage() {
  const { t } = useTranslation();
  const { tenantName } = useBranding();
  const offerings = listItems<OfferingResponse>(useOfferings()).slice(0, 3);
  const packages = listItems<PackageResponse>(usePackages()).slice(0, 3);

  return (
    <div className="flex flex-col gap-8">
      <section className="flex flex-col items-start gap-4 rounded-lg bg-surface p-6 sm:p-10">
        <p className="text-sm font-medium text-primary">{tenantName}</p>
        <h1 className="text-2xl font-bold sm:text-3xl">{t('home.heroTitle')}</h1>
        <p className="max-w-prose text-muted-foreground">{t('home.heroSubtitle')}</p>
        <div className="flex flex-wrap gap-2">
          <Button asChild>
            <Link to="/schedule">{t('home.browseSchedule')}</Link>
          </Button>
          <Button asChild variant="outline">
            <Link to="/packages">{t('home.viewPackages')}</Link>
          </Button>
        </div>
      </section>

      {offerings.length > 0 ? (
        <section className="flex flex-col gap-3">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-semibold">Programs</h2>
            <Link
              to="/schedule"
              className="inline-flex items-center gap-1 text-sm font-medium text-primary hover:underline"
            >
              All sessions <ArrowRight className="h-3.5 w-3.5" aria-hidden="true" />
            </Link>
          </div>
          <ul className="grid gap-3 sm:grid-cols-3">
            {offerings.map((offering) => (
              <li key={offering.id}>
                <Card>
                  <CardContent className="flex flex-col gap-1 pt-4">
                    <Link to={`/offerings/${offering.id}`} className="font-medium hover:underline">
                      {offering.name}
                    </Link>
                    <span className="text-sm capitalize text-muted-foreground">
                      {offering.format.replace(/_/g, ' ')} · {offering.duration_minutes} min
                    </span>
                    <span className="text-sm">
                      {offering.credit_cost} session{offering.credit_cost === 1 ? '' : 's'}
                    </span>
                  </CardContent>
                </Card>
              </li>
            ))}
          </ul>
        </section>
      ) : null}

      {packages.length > 0 ? (
        <section className="flex flex-col gap-3">
          <div className="flex items-center justify-between">
            <h2 className="text-lg font-semibold">Packages</h2>
            <Link
              to="/packages"
              className="inline-flex items-center gap-1 text-sm font-medium text-primary hover:underline"
            >
              All packages <ArrowRight className="h-3.5 w-3.5" aria-hidden="true" />
            </Link>
          </div>
          <ul className="grid gap-3 sm:grid-cols-3">
            {packages.map((item) => (
              <li key={item.id}>
                <Card>
                  <CardContent className="flex flex-col gap-1 pt-4">
                    <Link to={`/packages/${item.id}`} className="font-medium hover:underline">
                      {item.name}
                    </Link>
                    <span className="text-sm text-muted-foreground">
                      {item.credit_quantity} session{item.credit_quantity === 1 ? '' : 's'}
                    </span>
                    <Money amountMinor={item.price} className="font-semibold" />
                  </CardContent>
                </Card>
              </li>
            ))}
          </ul>
        </section>
      ) : null}
    </div>
  );
}
