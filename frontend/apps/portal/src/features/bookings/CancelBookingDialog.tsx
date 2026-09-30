import { useQueryClient } from '@tanstack/react-query';
import { Badge, ConfirmDialog, useToast } from '@scb/ui';
import {
  bookingsQueryKey,
  cancelPreviewQueryKey,
  useCancelBooking,
  useCancelPreview,
  type CancelPreview,
  type PolicyOutcome,
} from '../../api/endpoints';
import { body, errorMessage } from '../shared/api-utils';
import { Money } from '../shared/Money';

function outcomeLabel(outcome: PolicyOutcome | undefined): string {
  if (!outcome) return 'No outcome information available.';
  if (outcome.credit_outcome === 'return') return 'Your sessions will be returned.';
  if (outcome.credit_outcome === 'forfeit') return 'Sessions for this booking will be forfeited.';
  if (typeof outcome.refund_amount?.amount === 'number' && outcome.refund_amount.amount > 0) {
    return 'A refund will be issued to your original payment method.';
  }
  if (outcome.allowed === false) return outcome.reason ?? 'This booking cannot be cancelled.';
  return outcome.reason ?? 'This booking can be cancelled.';
}

export function CancelBookingDialog({
  bookingId,
  open,
  onOpenChange,
}: {
  bookingId: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const query = useCancelPreview(bookingId, {
    query: { queryKey: cancelPreviewQueryKey(bookingId), enabled: open, retry: false },
  });
  const cancel = useCancelBooking();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const preview = body<CancelPreview>(query);
  const outcome = preview?.outcome as PolicyOutcome | undefined;
  const refund = outcome?.refund_amount;

  const confirm = async () => {
    try {
      await cancel.mutateAsync({ id: bookingId, data: {} });
      await queryClient.invalidateQueries({ queryKey: bookingsQueryKey() });
      toast({ title: 'Booking cancelled', variant: 'success' });
      onOpenChange(false);
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  return (
    <ConfirmDialog
      open={open}
      onOpenChange={onOpenChange}
      title="Cancel this booking?"
      description={
        <span className="flex flex-col gap-2">
          <span>
            {query.isLoading ? 'Checking what happens if you cancel…' : outcomeLabel(outcome)}
          </span>
          {refund && refund.amount > 0 ? (
            <span className="flex items-center gap-1">
              Refund: <Money amountMinor={refund.amount} />
            </span>
          ) : null}
          {outcome?.credit_outcome === 'return' ? (
            <Badge variant="success">Sessions returned</Badge>
          ) : null}
        </span>
      }
      confirmLabel="Cancel booking"
      cancelLabel="Keep booking"
      destructive
      loading={cancel.isPending}
      onConfirm={() => void confirm()}
    />
  );
}
