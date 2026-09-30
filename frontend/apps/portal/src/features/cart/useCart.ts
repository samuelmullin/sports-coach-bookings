import { useQueryClient } from '@tanstack/react-query';
import {
  cartQueryKey,
  useAddCartLine,
  useApplyDiscount,
  useCart,
  useRemoveCartLine,
  useRemoveDiscount,
  useUpdateCartLine,
  type Cart,
  type CartPricing,
} from '../../api/endpoints';
import { useCustomerAuth } from '../../auth/customer-auth';
import { body } from '../shared/api-utils';
import { usePortalSettings } from '../shared/extras';
import { useGuestCart, type GuestLine, type GuestLineType } from './guest-cart';

function useInvalidateCartOnSuccess() {
  const queryClient = useQueryClient();
  return () => {
    void queryClient.invalidateQueries({ queryKey: cartQueryKey() });
  };
}

export function useAddToCart() {
  const onSuccess = useInvalidateCartOnSuccess();
  return useAddCartLine({ mutation: { onSuccess } });
}

export function useUpdateCartLineItem() {
  const onSuccess = useInvalidateCartOnSuccess();
  return useUpdateCartLine({ mutation: { onSuccess } });
}

export function useRemoveCartLineItem() {
  const onSuccess = useInvalidateCartOnSuccess();
  return useRemoveCartLine({ mutation: { onSuccess } });
}

export function useApplyCartDiscount() {
  const onSuccess = useInvalidateCartOnSuccess();
  return useApplyDiscount({ mutation: { onSuccess } });
}

export function useRemoveCartDiscount() {
  const onSuccess = useInvalidateCartOnSuccess();
  return useRemoveDiscount({ mutation: { onSuccess } });
}

export interface CartViewLine {
  id: string;
  type: GuestLineType;
  refId: string;
  title: string;
  subtitle?: string;
  quantity: number;
  unitPriceMinor: number;
  lineTotalMinor: number;
  currency: string;
  /** A guest drop-in awaiting a player before it can join the server cart. */
  pending: boolean;
  /** Local guest line id, present for guest and pending lines. */
  guestId?: string;
}

export interface CartView {
  mode: 'guest' | 'server';
  lines: CartViewLine[];
  /** Guest drop-ins that still need to be resolved with a player. */
  pendingLines: GuestLine[];
  itemCount: number;
  subtotalMinor: number;
  currency: string;
  isLoading: boolean;
}

function guestToViewLine(
  line: GuestLine,
  fallbackCurrency: string,
  pending: boolean,
): CartViewLine {
  const unitPriceMinor = line.snapshot.priceMinor ?? 0;
  return {
    id: guestLineId(line),
    type: line.type,
    refId: line.ref_id,
    title: line.snapshot.title,
    subtitle: line.snapshot.subtitle,
    quantity: line.quantity,
    unitPriceMinor,
    lineTotalMinor: unitPriceMinor * line.quantity,
    currency: line.snapshot.currency ?? fallbackCurrency,
    pending,
    guestId: line.id,
  };
}

function guestLineId(line: GuestLine): string {
  return `guest:${line.id}`;
}

export function useCartView(): CartView {
  const { status } = useCustomerAuth();
  const settings = usePortalSettings();
  const guestLines = useGuestCart();
  const authenticated = status === 'authenticated';

  const query = useCart({ query: { queryKey: cartQueryKey(), enabled: authenticated } });
  const cart = body<Cart>(query);
  const pricing = cart?.pricing as CartPricing | null | undefined;

  if (!authenticated) {
    const lines = guestLines.map((line) => guestToViewLine(line, settings.currency, false));
    return {
      mode: 'guest',
      lines,
      pendingLines: [],
      itemCount: lines.reduce((sum, line) => sum + line.quantity, 0),
      subtotalMinor: lines.reduce((sum, line) => sum + line.lineTotalMinor, 0),
      currency: guestLines[0]?.snapshot.currency ?? settings.currency,
      isLoading: status === 'loading',
    };
  }

  const pricingByRef = new Map<string, NonNullable<CartPricing['lines']>[number]>();
  for (const priced of pricing?.lines ?? []) {
    if (priced.type && priced.ref_id) pricingByRef.set(`${priced.type}:${priced.ref_id}`, priced);
  }

  const serverLines: CartViewLine[] = (cart?.lines ?? []).map((line) => {
    const priced = pricingByRef.get(`${line.type}:${line.ref_id}`);
    const quantity = line.quantity ?? 1;
    const unitPriceMinor = priced?.unit_price ?? 0;
    return {
      id: line.id,
      type: line.type as GuestLineType,
      refId: line.ref_id,
      title: priced?.description ?? line.type.replace(/_/g, ' '),
      quantity,
      unitPriceMinor,
      lineTotalMinor: priced?.line_total ?? unitPriceMinor * quantity,
      currency: settings.currency,
      pending: false,
    };
  });

  const pendingLines = guestLines.filter((line) => line.type === 'drop_in');
  const pendingAsView = pendingLines.map((line) => guestToViewLine(line, settings.currency, true));
  const lines = [...serverLines, ...pendingAsView];

  return {
    mode: 'server',
    lines,
    pendingLines,
    itemCount: lines.reduce((sum, line) => sum + line.quantity, 0),
    subtotalMinor: pricing?.subtotal ?? 0,
    currency: settings.currency,
    isLoading: query.isLoading,
  };
}
