import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Plus } from 'lucide-react';
import { Badge, Button, Card, CardContent, EmptyState, MoneyDisplay, Select, Table } from '@scb/ui';
import { useOrders } from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';

const STATUSES = [
  'pending_payment',
  'paid',
  'expired',
  'cancelled',
  'refunded',
  'partially_refunded',
];

export function OrdersPage() {
  const [status, setStatus] = useState('');
  const query = useOrders({ status: status || undefined, limit: 25 });
  const orders = listItems<{
    id: string;
    number: string;
    status: string;
    total: number;
    currency: string;
    paid_at?: string | null;
  }>(query);
  const navigate = useNavigate();

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Orders"
        description="Purchases, payments and refunds."
        actions={
          <Button onClick={() => navigate('/orders/new')}>
            <Plus className="h-4 w-4" aria-hidden="true" />
            New offline order
          </Button>
        }
      />

      <Card>
        <CardContent className="pt-4">
          <Select
            aria-label="Filter by status"
            className="max-w-xs"
            value={status}
            onValueChange={setStatus}
            options={[
              { value: '', label: 'All statuses' },
              ...STATUSES.map((value) => ({ value, label: value.replace('_', ' ') })),
            ]}
          />
        </CardContent>
      </Card>

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {orders.length === 0 ? (
          <EmptyState
            title="No orders"
            description="Orders will appear here once customers check out."
          />
        ) : (
          <Table
            caption="Orders"
            rowKey={(row) => row.id}
            onRowClick={(row) => navigate(`/orders/${row.id}`)}
            columns={[
              {
                key: 'number',
                header: 'Order',
                cell: (row) => (
                  <Link
                    className="font-medium text-primary hover:underline"
                    to={`/orders/${row.id}`}
                  >
                    {row.number}
                  </Link>
                ),
              },
              {
                key: 'status',
                header: 'Status',
                cell: (row) => <Badge variant="secondary">{row.status.replace('_', ' ')}</Badge>,
              },
              {
                key: 'total',
                header: 'Total',
                align: 'right',
                cell: (row) => <MoneyDisplay amountMinor={row.total} currency={row.currency} />,
              },
              {
                key: 'paid',
                header: 'Paid',
                cell: (row) => (row.paid_at ? new Date(row.paid_at).toLocaleString() : '—'),
              },
            ]}
            data={orders}
          />
        )}
      </QueryState>
    </div>
  );
}
