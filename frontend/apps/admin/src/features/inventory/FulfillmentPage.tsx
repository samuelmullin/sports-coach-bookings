import { useState } from 'react';
import { Badge, Button, Card, CardContent, EmptyState, Select, Table, useToast } from '@scb/ui';
import {
  useFulfillments,
  useMarkFulfillmentPickedUp,
  useMarkFulfillmentReady,
  type Fulfillment,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';

export function FulfillmentPage() {
  const [status, setStatus] = useState('ready');
  const query = useFulfillments({ status: status || undefined, limit: 50 });
  const fulfillments = listItems<Fulfillment>(query);
  const ready = useMarkFulfillmentReady();
  const pickup = useMarkFulfillmentPickedUp();
  const { toast } = useToast();

  return (
    <div className="flex flex-col gap-4">
      <PageHeader title="Fulfillment" description="Orders waiting to be picked up." />

      <Card>
        <CardContent className="pt-4">
          <Select
            aria-label="Filter by status"
            className="max-w-xs"
            value={status}
            onValueChange={setStatus}
            options={[
              { value: '', label: 'All' },
              { value: 'pending', label: 'Pending' },
              { value: 'ready_for_pickup', label: 'Ready for pickup' },
              { value: 'picked_up', label: 'Picked up' },
            ]}
          />
        </CardContent>
      </Card>

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {fulfillments.length === 0 ? (
          <EmptyState title="Nothing to fulfill" description="Paid product orders appear here." />
        ) : (
          <Card>
            <CardContent className="pt-4">
              <Table
                caption="Fulfillments"
                rowKey={(row) => row.id}
                columns={[
                  { key: 'order', header: 'Order line', cell: (row) => row.order_line_id },
                  { key: 'variant', header: 'Variant', cell: (row) => row.variant_id ?? '—' },
                  {
                    key: 'status',
                    header: 'Status',
                    cell: (row) => (
                      <Badge variant={row.status === 'picked_up' ? 'success' : 'warning'}>
                        {row.status.replace('_', ' ')}
                      </Badge>
                    ),
                  },
                  {
                    key: 'actions',
                    header: '',
                    align: 'right',
                    cell: (row) => (
                      <div className="flex justify-end gap-1">
                        {row.status !== 'ready_for_pickup' && row.status !== 'picked_up' ? (
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() =>
                              void ready
                                .mutateAsync({ id: row.id })
                                .then(() => {
                                  toast({ title: 'Marked ready', variant: 'success' });
                                  void query.refetch();
                                })
                                .catch((error) =>
                                  toast({ title: errorMessage(error), variant: 'danger' }),
                                )
                            }
                          >
                            Mark ready
                          </Button>
                        ) : null}
                        {row.status !== 'picked_up' ? (
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() =>
                              void pickup
                                .mutateAsync({ id: row.id })
                                .then(() => {
                                  toast({ title: 'Marked picked up', variant: 'success' });
                                  void query.refetch();
                                })
                                .catch((error) =>
                                  toast({ title: errorMessage(error), variant: 'danger' }),
                                )
                            }
                          >
                            Picked up
                          </Button>
                        ) : null}
                      </div>
                    ),
                  },
                ]}
                data={fulfillments}
              />
            </CardContent>
          </Card>
        )}
      </QueryState>
    </div>
  );
}
