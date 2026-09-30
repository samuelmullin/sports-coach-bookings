import { Button, useToast } from '@scb/ui';
import { useCustomerAuth } from '../../auth/customer-auth';
import { errorCode, errorMessage } from '../shared/api-utils';
import { friendlyError } from '../shared/errors';
import { addGuestLine, guestLineId, type GuestLineType } from './guest-cart';
import { useAddToCart } from './useCart';

export function AddToCartButton({
  type,
  refId,
  quantity = 1,
  disabled,
  label = 'Add to cart',
  title,
  subtitle,
  priceMinor,
  currency,
  sessionId,
  startsAt,
  venueName,
}: {
  type: GuestLineType;
  refId: string;
  quantity?: number;
  disabled?: boolean;
  label?: string;
  title?: string;
  subtitle?: string;
  priceMinor?: number;
  currency?: string;
  sessionId?: string;
  startsAt?: string;
  venueName?: string;
}) {
  const { status } = useCustomerAuth();
  const mutation = useAddToCart();
  const { toast } = useToast();

  const addGuest = () => {
    addGuestLine({
      id: guestLineId(type, refId),
      type,
      ref_id: refId,
      quantity,
      snapshot: {
        title: title ?? 'Item',
        subtitle,
        priceMinor,
        currency,
        sessionId,
        startsAt,
        venueName,
      },
    });
    toast({ title: 'Added to cart', variant: 'success' });
  };

  const addServer = async () => {
    try {
      await mutation.mutateAsync({ data: { type, ref_id: refId, quantity } });
      toast({ title: 'Added to cart', variant: 'success' });
    } catch (error) {
      toast({
        title: friendlyError(errorCode(error), errorMessage(error)),
        variant: 'danger',
      });
    }
  };

  const authenticated = status === 'authenticated';

  return (
    <Button
      onClick={() => (authenticated ? void addServer() : addGuest())}
      disabled={disabled || (authenticated && mutation.isPending)}
    >
      {authenticated && mutation.isPending ? 'Adding…' : label}
    </Button>
  );
}
