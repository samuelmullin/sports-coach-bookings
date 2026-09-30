import { Link, useParams } from 'react-router-dom';
import { ArrowLeft } from 'lucide-react';
import { Badge, Button, Card, CardContent } from '@scb/ui';
import {
  useOfferings,
  usePackages,
  type OfferingResponse,
  type PackageResponse,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { Money } from '../shared/Money';
import { usePortalSettings } from '../shared/extras';
import { AddToCartButton } from '../cart/AddToCartButton';

export function PackageDetailPage() {
  const { packageId } = useParams<{ packageId: string }>();
  const settings = usePortalSettings();
  const query = usePackages();
  const offeringsQuery = useOfferings();
  const packages = listItems<PackageResponse>(query);
  const offerings = listItems<OfferingResponse>(offeringsQuery);
  const item = packages.find((candidate) => candidate.id === packageId);

  const scopedOfferingIds = item?.offering_ids ?? [];
  const scopedOfferingNames = scopedOfferingIds
    .map((id) => offerings.find((offering) => offering.id === id)?.name)
    .filter((name): name is string => Boolean(name));

  return (
    <div className="flex flex-col gap-4">
      <Button asChild variant="ghost" size="sm" className="self-start">
        <Link to="/packages">
          <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Back to packages
        </Link>
      </Button>

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {!item ? (
          <p className="text-sm text-muted-foreground">This package is not available.</p>
        ) : (
          <>
            <PageHeader
              title={item.name}
              description={item.description ?? undefined}
              actions={
                <AddToCartButton
                  type="package"
                  refId={item.id}
                  title={item.name}
                  subtitle={item.description ?? undefined}
                  priceMinor={item.price}
                  currency={settings.currency}
                />
              }
            />
            <div className="flex flex-wrap items-center gap-2">
              <Badge variant="accent">
                {item.credit_quantity} session{item.credit_quantity === 1 ? '' : 's'}
              </Badge>
              {item.validity_days ? (
                <Badge variant="outline">Valid {item.validity_days} days</Badge>
              ) : null}
              {item.per_household_limit ? (
                <Badge variant="outline">Limit {item.per_household_limit} per household</Badge>
              ) : null}
              {scopedOfferingIds.length > 0 ? (
                <Badge variant="outline">
                  Valid for:{' '}
                  {scopedOfferingNames.join(', ') || `${scopedOfferingIds.length} offering(s)`}
                </Badge>
              ) : (
                <Badge variant="outline">Any offering</Badge>
              )}
            </div>
            <Card>
              <CardContent className="flex flex-col gap-2 pt-4 text-sm">
                <div className="flex items-center justify-between">
                  <span className="text-muted-foreground">Price</span>
                  <Money amountMinor={item.price} className="text-lg font-semibold" />
                </div>
                {item.taxable ? (
                  <p className="text-xs text-muted-foreground">Taxes calculated at checkout.</p>
                ) : null}
              </CardContent>
            </Card>

            <Card className="border-dashed">
              <CardContent className="pt-4 text-sm text-muted-foreground">
                Sessions are added to your household after purchase and can be used to book eligible
                sessions.
              </CardContent>
            </Card>
          </>
        )}
      </QueryState>
    </div>
  );
}
