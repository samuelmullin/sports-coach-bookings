import { useEffect, useRef } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { useCustomerAuth } from '../../auth/customer-auth';
import { useGuestCart } from './guest-cart';
import { mergeGuestCartIntoServer } from './merge';

/**
 * Runs once when a session becomes authenticated with a non-empty guest cart,
 * merging package/product lines into the server cart. Pending guest drop-ins
 * stay behind for the cart page to resolve with a player.
 */
export function GuestCartMerge() {
  const { status } = useCustomerAuth();
  const queryClient = useQueryClient();
  const guestLines = useGuestCart();
  const merged = useRef(false);

  useEffect(() => {
    if (status !== 'authenticated') {
      merged.current = false;
      return;
    }
    if (merged.current || guestLines.length === 0) return;
    merged.current = true;
    void mergeGuestCartIntoServer(queryClient);
  }, [status, guestLines, queryClient]);

  return null;
}
