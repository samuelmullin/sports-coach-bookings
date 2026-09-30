import { PackageCheck } from 'lucide-react';
import { Badge, Card, CardContent, EmptyState } from '@scb/ui';
import { usePickups, type Pickup } from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { VenueTime } from '../shared/VenueTime';
import { usePortalSettings } from '../shared/extras';

const STATUS_VARIANT: Record<string, 'success' | 'warning' | 'outline' | 'danger'> = {
  pending: 'warning',
  ready_for_pickup: 'success',
  picked_up: 'outline',
  cancelled: 'danger',
};

const STATUS_LABEL: Record<string, string> = {
  pending: 'Preparing',
  ready_for_pickup: 'Ready for pickup',
  picked_up: 'Picked up',
  cancelled: 'Cancelled',
};

export function PickupsPage() {
  const settings = usePortalSettings();
  const query = usePickups();
  const pickups = listItems<Pickup>(query);

  return (
    <div className="flex flex-col gap-4">
      <PageHeader title="Pickups" description="Track merchandise orders ready to collect." />
      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {pickups.length === 0 ? (
          <EmptyState
            icon={<PackageCheck className="h-8 w-8" />}
            title="Nothing to pick up"
            description="Merchandise you order will appear here."
          />
        ) : (
          <ul className="flex flex-col gap-3">
            {pickups.map((pickup) => (
              <li key={pickup.id}>
                <Card>
                  <CardContent className="flex flex-wrap items-center justify-between gap-3 pt-4">
                    <div className="flex flex-col gap-0.5">
                      <span className="font-medium">{pickup.product_name ?? 'Merchandise'}</span>
                      {pickup.option_values && Object.keys(pickup.option_values).length > 0 ? (
                        <span className="text-sm text-muted-foreground">
                          {Object.entries(pickup.option_values)
                            .map(([key, value]) => `${key}: ${value}`)
                            .join(' · ')}
                        </span>
                      ) : null}
                      {pickup.picked_up_at ? (
                        <VenueTime
                          instant={pickup.picked_up_at}
                          timezone={settings.timezone}
                          pattern="MMM d, yyyy"
                          className="text-xs text-muted-foreground"
                        />
                      ) : null}
                    </div>
                    <Badge variant={STATUS_VARIANT[pickup.status] ?? 'outline'}>
                      {STATUS_LABEL[pickup.status] ?? pickup.status}
                    </Badge>
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
