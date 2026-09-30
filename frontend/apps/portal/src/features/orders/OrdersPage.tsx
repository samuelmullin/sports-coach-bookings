import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { ShoppingCart } from 'lucide-react';
import { Badge, Card, CardContent, EmptyState } from '@scb/ui';
import { useOrders, type OrderSummary } from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { Money } from '../shared/Money';
import { VenueTime } from '../shared/VenueTime';
import { usePortalSettings } from '../shared/extras';

const STATUS_VARIANT: Record<string, 'success' | 'warning' | 'outline' | 'danger'> = {
  paid: 'success',
  pending_payment: 'warning',
  expired: 'outline',
  cancelled: 'outline',
  refunded: 'danger',
  partially_refunded: 'warning',
};

export function OrdersPage() {
  const { t } = useTranslation();
  const settings = usePortalSettings();
  const query = useOrders({ limit: 25 });
  const orders = listItems<OrderSummary>(query);

  return (
    <div className="flex flex-col gap-4">
      <PageHeader title={t('nav.orders')} description={t('orders.subtitle')} />
      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {orders.length === 0 ? (
          <EmptyState
            icon={<ShoppingCart className="h-8 w-8" />}
            title={t('empty.orders')}
            description="Your purchases and receipts will appear here."
          />
        ) : (
          <ul className="flex flex-col gap-3">
            {orders.map((order) => (
              <li key={order.id}>
                <Card>
                  <CardContent className="flex flex-wrap items-center justify-between gap-3 pt-4">
                    <div className="flex flex-col gap-0.5">
                      <span className="font-medium">Order {order.number}</span>
                      {order.inserted_at ? (
                        <VenueTime
                          instant={order.inserted_at}
                          timezone={settings.timezone}
                          pattern="MMM d, yyyy"
                          className="text-sm text-muted-foreground"
                        />
                      ) : null}
                      <span className="text-sm text-muted-foreground">
                        {(order.lines ?? []).length} item(s)
                      </span>
                    </div>
                    <div className="flex items-center gap-3">
                      <Badge variant={STATUS_VARIANT[order.status] ?? 'outline'}>
                        {order.status.replace(/_/g, ' ')}
                      </Badge>
                      <Money amountMinor={order.total} className="font-semibold" />
                      <Link
                        to={`/orders/${order.id}`}
                        className="text-sm font-medium text-primary hover:underline"
                      >
                        Details
                      </Link>
                    </div>
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
