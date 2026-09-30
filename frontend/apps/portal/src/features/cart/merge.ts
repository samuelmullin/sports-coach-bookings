import type { QueryClient } from '@tanstack/react-query';
import { sportsCoachBookingsWebPortalCartCartControllerAddLine } from '@scb/api-client';
import { cartQueryKey } from '../../api/endpoints';
import { readGuestCart, removeGuestLine } from './guest-cart';

/**
 * Moves guest package/product lines into the server cart after auth.
 *
 * Drop-in lines are intentionally left in the guest store as *pending*: a paid
 * drop-in needs a held booking (which needs an authenticated household and a
 * chosen player), so the cart page resolves them explicitly.
 *
 * A failed line stays in the guest cart and does not block the others.
 */
export async function mergeGuestCartIntoServer(queryClient: QueryClient): Promise<void> {
  let merged = false;

  for (const line of readGuestCart()) {
    if (line.type === 'drop_in') continue;
    try {
      await sportsCoachBookingsWebPortalCartCartControllerAddLine({
        type: line.type,
        ref_id: line.ref_id,
        quantity: line.quantity,
      });
      removeGuestLine(line.id);
      merged = true;
    } catch {
      // Keep the line so it can be retried; continue with the rest.
    }
  }

  if (merged) {
    await queryClient.invalidateQueries({ queryKey: cartQueryKey() });
  }
}
