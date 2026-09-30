import { useState } from 'react';
import { Button, FormField, Input, Modal, Select, Switch, useToast } from '@scb/ui';
import { useRefundOrder } from '../../api/endpoints';
import { errorMessage } from '../shared/api-utils';
import { useTenantSettings } from '../shared/useTenantSettings';

interface Line {
  id?: string;
  description?: string;
  line_total?: number;
  refunded_amount?: number;
  type?: string;
}

export function RefundDialog({
  open,
  onOpenChange,
  orderId,
  lines,
  onRefunded,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  orderId: string;
  lines: Line[];
  onRefunded?: () => void;
}) {
  const refund = useRefundOrder();
  const { toast } = useToast();
  const { currency } = useTenantSettings();
  const [lineId, setLineId] = useState('');
  const [reason, setReason] = useState('');
  const [force, setForce] = useState(false);

  const selectedLine = lines.find((line) => line.id === lineId);
  const hasUsedCredits = selectedLine?.type === 'package';

  const submit = async () => {
    try {
      await refund.mutateAsync({
        id: orderId,
        data: {
          order_line_id: lineId || null,
          force,
          reason: reason || null,
          amount: null,
        },
      });
      toast({ title: 'Refund processed', variant: 'success' });
      onOpenChange(false);
      setLineId('');
      setReason('');
      setForce(false);
      onRefunded?.();
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  return (
    <Modal
      open={open}
      onOpenChange={onOpenChange}
      title="Refund order"
      description={`Refunds are issued in ${currency}.`}
      footer={
        <>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button variant="danger" onClick={() => void submit()} disabled={refund.isPending}>
            Refund
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        <FormField label="Line" help="Choose a single line, or refund every open line.">
          <Select
            aria-label="Line"
            value={lineId}
            onValueChange={setLineId}
            options={[
              { value: '', label: 'All open lines' },
              ...lines
                .filter((line) => line.id)
                .map((line) => ({
                  value: line.id as string,
                  label: `${line.description ?? 'Line'} (${((line.line_total ?? 0) / 100).toFixed(2)})`,
                })),
            ]}
          />
        </FormField>

        {hasUsedCredits ? (
          <label className="flex flex-col gap-2 rounded-md border border-amber-300 bg-amber-50 p-2 text-xs text-amber-900">
            <span>
              This is a package line. Sessions may already have been used. Enable force to refund
              anyway (this is audited).
            </span>
            <Switch label="Force refund used sessions" checked={force} onCheckedChange={setForce} />
          </label>
        ) : null}

        <FormField label="Reason">
          <Input value={reason} onChange={(event) => setReason(event.target.value)} />
        </FormField>
      </div>
    </Modal>
  );
}
