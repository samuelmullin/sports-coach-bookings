import { Link, useParams } from 'react-router-dom';
import { ArrowLeft, Printer } from 'lucide-react';
import { Badge, Button, Card, CardContent, MoneyDisplay } from '@scb/ui';
import { useOrder, orderQueryKey, type OrderDetail } from '../../api/endpoints';
import { body, errorMessage } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { VenueTime } from '../shared/VenueTime';
import { usePortalSettings } from '../shared/extras';

export function OrderDetailPage() {
  const { orderId = '' } = useParams<{ orderId: string }>();
  const settings = usePortalSettings();
  const query = useOrder(orderId, {
    query: { queryKey: orderQueryKey(orderId), enabled: Boolean(orderId), retry: false },
  });
  const order = body<OrderDetail>(query);
  const currency = order?.currency ?? settings.currency;

  return (
    <div className="flex flex-col gap-4">
      <Button asChild variant="ghost" size="sm" className="self-start print:hidden">
        <Link to="/orders">
          <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Back to orders
        </Link>
      </Button>

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {!order ? (
          <p className="text-sm text-muted-foreground">This order could not be found.</p>
        ) : (
          <>
            <PageHeader
              title={`Order ${order.number}`}
              description={
                order.inserted_at ? (
                  <VenueTime instant={order.inserted_at} timezone={settings.timezone} />
                ) : undefined
              }
              actions={
                <Button variant="outline" onClick={() => window.print()}>
                  <Printer className="h-4 w-4" aria-hidden="true" /> Print receipt
                </Button>
              }
            />

            <Badge variant="outline" className="self-start">
              {order.status.replace(/_/g, ' ')}
            </Badge>

            <Card>
              <CardContent className="flex flex-col gap-3 pt-4">
                <ul className="flex flex-col divide-y divide-border">
                  {(order.lines ?? []).map((line) => (
                    <li
                      key={line.id}
                      className="flex items-start justify-between gap-3 py-2 text-sm"
                    >
                      <div className="flex flex-col">
                        <span className="font-medium">
                          {(line.quantity ?? 1) > 1 ? `${line.quantity} × ` : ''}
                          {line.description}
                        </span>
                        <span className="text-xs capitalize text-muted-foreground">
                          {(line.type ?? 'item').replace(/_/g, ' ')}
                        </span>
                      </div>
                      <MoneyDisplay amountMinor={line.line_total ?? 0} currency={currency} />
                    </li>
                  ))}
                </ul>

                <dl className="flex flex-col gap-1 border-t border-border pt-3 text-sm">
                  <div className="flex justify-between">
                    <dt className="text-muted-foreground">Subtotal</dt>
                    <dd>
                      <MoneyDisplay amountMinor={order.subtotal ?? 0} currency={currency} />
                    </dd>
                  </div>
                  {(order.discount_total ?? 0) > 0 ? (
                    <div className="flex justify-between">
                      <dt className="text-muted-foreground">Discount</dt>
                      <dd>
                        −
                        <MoneyDisplay amountMinor={order.discount_total ?? 0} currency={currency} />
                      </dd>
                    </div>
                  ) : null}
                  <div className="flex justify-between">
                    <dt className="text-muted-foreground">Tax</dt>
                    <dd>
                      <MoneyDisplay amountMinor={order.tax_total ?? 0} currency={currency} />
                    </dd>
                  </div>
                  <div className="flex justify-between text-base font-semibold">
                    <dt>Total</dt>
                    <dd>
                      <MoneyDisplay amountMinor={order.total} currency={currency} />
                    </dd>
                  </div>
                  {(order.refunded_total ?? 0) > 0 ? (
                    <div className="flex justify-between text-danger">
                      <dt>Refunded</dt>
                      <dd>
                        −
                        <MoneyDisplay amountMinor={order.refunded_total ?? 0} currency={currency} />
                      </dd>
                    </div>
                  ) : null}
                </dl>

                {order.paid_at ? (
                  <p className="text-xs text-muted-foreground">
                    Paid <VenueTime instant={order.paid_at} timezone={settings.timezone} /> via{' '}
                    {order.payment_method ?? 'online'} payment.
                  </p>
                ) : null}
              </CardContent>
            </Card>
          </>
        )}
      </QueryState>
    </div>
  );
}
