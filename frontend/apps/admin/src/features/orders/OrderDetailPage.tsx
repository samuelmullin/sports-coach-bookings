import { useState } from 'react';
import { useParams } from 'react-router-dom';
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  MoneyDisplay,
  Table,
} from '@scb/ui';
import { useOrder, type OrderDetail } from '../../api/endpoints';
import { body, errorMessage } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';
import { RefundDialog } from './RefundDialog';

export function OrderDetailPage() {
  const { orderId = '' } = useParams();
  const query = useOrder(orderId);
  const order = body<OrderDetail>(query);
  const [refundOpen, setRefundOpen] = useState(false);

  const lines = order?.lines ?? [];

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title={order?.number ?? 'Order'}
        description={order ? `${order.status.replace('_', ' ')} · ${order.currency}` : undefined}
        actions={
          <Button
            variant="danger"
            size="sm"
            disabled={!order || order.status === 'refunded'}
            onClick={() => setRefundOpen(true)}
          >
            Refund
          </Button>
        }
      />

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {order ? (
          <>
            <div className="flex flex-wrap gap-2">
              <Badge variant="secondary">{order.status.replace('_', ' ')}</Badge>
              {order.payment_method ? (
                <Badge variant="outline">{order.payment_method}</Badge>
              ) : null}
              {order.refunded_total ? (
                <Badge variant="warning">
                  Refunded{' '}
                  <MoneyDisplay amountMinor={order.refunded_total} currency={order.currency} />
                </Badge>
              ) : null}
            </div>

            <Card>
              <CardHeader>
                <CardTitle>Lines</CardTitle>
              </CardHeader>
              <CardContent>
                <Table
                  caption="Order lines"
                  rowKey={(row) => row.id ?? row.description ?? ''}
                  columns={[
                    {
                      key: 'description',
                      header: 'Description',
                      cell: (row) => row.description ?? '—',
                    },
                    { key: 'type', header: 'Type', cell: (row) => row.type ?? '—' },
                    { key: 'qty', header: 'Qty', cell: (row) => row.quantity ?? 1 },
                    {
                      key: 'unit',
                      header: 'Unit',
                      align: 'right',
                      cell: (row) => (
                        <MoneyDisplay amountMinor={row.unit_price ?? 0} currency={order.currency} />
                      ),
                    },
                    {
                      key: 'total',
                      header: 'Line total',
                      align: 'right',
                      cell: (row) => (
                        <MoneyDisplay amountMinor={row.line_total ?? 0} currency={order.currency} />
                      ),
                    },
                    {
                      key: 'refunded',
                      header: 'Refunded',
                      align: 'right',
                      cell: (row) =>
                        row.refunded_amount ? (
                          <MoneyDisplay
                            amountMinor={row.refunded_amount}
                            currency={order.currency}
                          />
                        ) : (
                          '—'
                        ),
                    },
                  ]}
                  data={lines}
                />

                <dl className="mt-4 flex flex-col gap-1 text-sm">
                  <div className="flex justify-between">
                    <dt className="text-muted-foreground">Subtotal</dt>
                    <dd>
                      <MoneyDisplay amountMinor={order.subtotal ?? 0} currency={order.currency} />
                    </dd>
                  </div>
                  <div className="flex justify-between">
                    <dt className="text-muted-foreground">Discount</dt>
                    <dd>
                      <MoneyDisplay
                        amountMinor={order.discount_total ?? 0}
                        currency={order.currency}
                      />
                    </dd>
                  </div>
                  <div className="flex justify-between">
                    <dt className="text-muted-foreground">Tax</dt>
                    <dd>
                      <MoneyDisplay amountMinor={order.tax_total ?? 0} currency={order.currency} />
                    </dd>
                  </div>
                  <div className="flex justify-between font-semibold">
                    <dt>Total</dt>
                    <dd>
                      <MoneyDisplay amountMinor={order.total} currency={order.currency} />
                    </dd>
                  </div>
                </dl>
              </CardContent>
            </Card>

            <RefundDialog
              open={refundOpen}
              onOpenChange={setRefundOpen}
              orderId={orderId}
              lines={lines}
              onRefunded={() => void query.refetch()}
            />
          </>
        ) : null}
      </QueryState>
    </div>
  );
}
