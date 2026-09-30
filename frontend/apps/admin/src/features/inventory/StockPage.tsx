import { useState } from 'react';
import {
  Badge,
  Button,
  Card,
  CardContent,
  EmptyState,
  FormField,
  Input,
  Modal,
  Table,
  useToast,
} from '@scb/ui';
import {
  useAdjustStock,
  useProducts,
  useReceiveStock,
  useStockLevels,
  useStockMovements,
  useVariants,
  type StockLevel,
  type StockMovement,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';

export function StockPage() {
  const levelsQuery = useStockLevels({ limit: 50 });
  const levels = listItems<StockLevel>(levelsQuery);
  const products = listItems<{ id: string; name: string }>(useProducts());
  const variants = listItems<{ id: string; sku: string }>(useVariants(products[0]?.id ?? ''));
  const receive = useReceiveStock();
  const adjust = useAdjustStock();
  const { toast } = useToast();

  const [receiveFor, setReceiveFor] = useState<StockLevel | null>(null);
  const [adjustFor, setAdjustFor] = useState<StockLevel | null>(null);
  const [historyFor, setHistoryFor] = useState<StockLevel | null>(null);
  const [quantity, setQuantity] = useState(1);
  const [delta, setDelta] = useState(-1);
  const [note, setNote] = useState('');

  const movementsQuery = useStockMovements(historyFor?.variant_id ?? '', { limit: 25 });
  const movements = listItems<StockMovement>(movementsQuery);

  const labelFor = (variantId: string) =>
    variants.find((v) => v.id === variantId)?.sku ?? variantId;

  return (
    <div className="flex flex-col gap-4">
      <PageHeader title="Stock" description="On-hand inventory by variant." />

      <QueryState
        loading={levelsQuery.isLoading}
        error={levelsQuery.isError ? errorMessage(levelsQuery.error) : undefined}
        onRetry={() => void levelsQuery.refetch()}
      >
        {levels.length === 0 ? (
          <EmptyState
            title="No stock records"
            description="Stock appears once you create variants."
          />
        ) : (
          <Card>
            <CardContent className="pt-4">
              <Table
                caption="Stock levels"
                rowKey={(row) => row.id}
                columns={[
                  { key: 'variant', header: 'Variant', cell: (row) => labelFor(row.variant_id) },
                  { key: 'on_hand', header: 'On hand', cell: (row) => row.on_hand },
                  { key: 'reserved', header: 'Reserved', cell: (row) => row.reserved },
                  {
                    key: 'available',
                    header: 'Available',
                    cell: (row) => (
                      <Badge variant={row.available <= 0 ? 'danger' : 'success'}>
                        {row.available}
                      </Badge>
                    ),
                  },
                  {
                    key: 'actions',
                    header: '',
                    align: 'right',
                    cell: (row) => (
                      <div className="flex justify-end gap-1">
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => {
                            setReceiveFor(row);
                            setQuantity(1);
                            setNote('');
                          }}
                        >
                          Receive
                        </Button>
                        <Button
                          variant="ghost"
                          size="sm"
                          onClick={() => {
                            setAdjustFor(row);
                            setDelta(-1);
                            setNote('');
                          }}
                        >
                          Adjust
                        </Button>
                        <Button variant="ghost" size="sm" onClick={() => setHistoryFor(row)}>
                          History
                        </Button>
                      </div>
                    ),
                  },
                ]}
                data={levels}
              />
            </CardContent>
          </Card>
        )}
      </QueryState>

      <Modal
        open={receiveFor !== null}
        onOpenChange={(open) => !open && setReceiveFor(null)}
        title="Receive stock"
        footer={
          <>
            <Button variant="outline" onClick={() => setReceiveFor(null)}>
              Cancel
            </Button>
            <Button
              onClick={() => {
                if (!receiveFor) return;
                void receive
                  .mutateAsync({
                    id: receiveFor.variant_id,
                    data: { quantity, note: note || null },
                  })
                  .then(() => {
                    toast({ title: 'Stock received', variant: 'success' });
                    setReceiveFor(null);
                    void levelsQuery.refetch();
                  })
                  .catch((error) => toast({ title: errorMessage(error), variant: 'danger' }));
              }}
              disabled={receive.isPending}
            >
              Receive
            </Button>
          </>
        }
      >
        <div className="flex flex-col gap-4">
          <FormField label="Quantity">
            <Input
              type="number"
              value={quantity}
              onChange={(e) => setQuantity(Number(e.target.value))}
            />
          </FormField>
          <FormField label="Note">
            <Input value={note} onChange={(e) => setNote(e.target.value)} />
          </FormField>
        </div>
      </Modal>

      <Modal
        open={adjustFor !== null}
        onOpenChange={(open) => !open && setAdjustFor(null)}
        title="Adjust stock"
        footer={
          <>
            <Button variant="outline" onClick={() => setAdjustFor(null)}>
              Cancel
            </Button>
            <Button
              onClick={() => {
                if (!adjustFor) return;
                void adjust
                  .mutateAsync({
                    id: adjustFor.variant_id,
                    data: { delta, reason: note || 'Manual adjustment' },
                  })
                  .then(() => {
                    toast({ title: 'Stock adjusted', variant: 'success' });
                    setAdjustFor(null);
                    void levelsQuery.refetch();
                  })
                  .catch((error) => toast({ title: errorMessage(error), variant: 'danger' }));
              }}
              disabled={adjust.isPending}
            >
              Adjust
            </Button>
          </>
        }
      >
        <div className="flex flex-col gap-4">
          <FormField label="Signed change">
            <Input type="number" value={delta} onChange={(e) => setDelta(Number(e.target.value))} />
          </FormField>
          <FormField label="Reason">
            <Input value={note} onChange={(e) => setNote(e.target.value)} />
          </FormField>
        </div>
      </Modal>

      <Modal
        open={historyFor !== null}
        onOpenChange={(open) => !open && setHistoryFor(null)}
        title="Movement history"
        size="lg"
      >
        {movements.length === 0 ? (
          <p className="text-sm text-muted-foreground">No movements recorded.</p>
        ) : (
          <Table
            caption="Stock movements"
            rowKey={(row) => row.id}
            columns={[
              { key: 'kind', header: 'Kind', cell: (row) => row.kind },
              {
                key: 'delta',
                header: 'Change',
                cell: (row) => (
                  <span className={row.delta >= 0 ? 'text-green-700' : 'text-danger'}>
                    {row.delta > 0 ? '+' : ''}
                    {row.delta}
                  </span>
                ),
              },
              { key: 'note', header: 'Note', cell: (row) => row.note ?? '—' },
              {
                key: 'when',
                header: 'When',
                cell: (row) => (row.inserted_at ? new Date(row.inserted_at).toLocaleString() : '—'),
              },
            ]}
            data={movements}
          />
        )}
      </Modal>
    </div>
  );
}
