import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { Package } from 'lucide-react';
import { Badge, Card, CardContent, EmptyState } from '@scb/ui';
import { usePackages, type PackageResponse } from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { Money } from '../shared/Money';

export function PackagesPage() {
  const { t } = useTranslation();
  const query = usePackages();
  const packages = listItems<PackageResponse>(query);

  return (
    <div className="flex flex-col gap-4">
      <PageHeader title={t('nav.packages')} description={t('packages.subtitle')} />
      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {packages.length === 0 ? (
          <EmptyState
            icon={<Package className="h-8 w-8" />}
            title={t('empty.packages')}
            description="Check back soon for new bundles."
          />
        ) : (
          <ul className="grid gap-3 sm:grid-cols-2">
            {packages.map((item) => (
              <li key={item.id}>
                <Card>
                  <CardContent className="flex flex-col gap-2 pt-4">
                    <div className="flex items-start justify-between gap-2">
                      <h2 className="font-medium">{item.name}</h2>
                      <Badge variant="accent">
                        {item.credit_quantity} session{item.credit_quantity === 1 ? '' : 's'}
                      </Badge>
                    </div>
                    {item.description ? (
                      <p className="text-sm text-muted-foreground">{item.description}</p>
                    ) : null}
                    <div className="flex items-center justify-between gap-2">
                      <Money amountMinor={item.price} className="font-semibold" />
                      <Link
                        to={`/packages/${item.id}`}
                        className="text-sm font-medium text-primary hover:underline"
                      >
                        View package
                      </Link>
                    </div>
                    {item.validity_days ? (
                      <p className="text-xs text-muted-foreground">
                        Valid for {item.validity_days} days after purchase
                      </p>
                    ) : null}
                  </CardContent>
                </Card>
              </li>
            ))}
          </ul>
        )}
      </QueryState>
    </div>
  );
}
