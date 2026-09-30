import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Trash2 } from 'lucide-react';
import {
  Badge,
  Button,
  Card,
  CardContent,
  EmptyState,
  Input,
  MoneyDisplay,
  useToast,
} from '@scb/ui';
import {
  cartQueryKey,
  useCart,
  useCheckout,
  usePlayers,
  useCreateBooking,
  type Cart,
  type CartPricing,
  type CheckoutResult,
  type PlayerResponse,
} from '../../api/endpoints';
import { body, errorCode, errorMessage, listItems, responseData } from '../shared/api-utils';
import { friendlyError } from '../shared/errors';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { PlayerSelect } from '../shared/PlayerSelect';
import { usePortalSettings } from '../shared/extras';
import { useCustomerAuth } from '../../auth/customer-auth';
import { removeGuestLine, updateGuestQuantity, type GuestLine } from './guest-cart';
import {
  useAddToCart,
  useApplyCartDiscount,
  useCartView,
  useRemoveCartDiscount,
  useRemoveCartLineItem,
  useUpdateCartLineItem,
} from './useCart';

export function redirectToCheckout(url: string): void {
  window.location.assign(url);
}

export function CartPage({
  onRedirect = redirectToCheckout,
}: {
  onRedirect?: (url: string) => void;
} = {}) {
  const settings = usePortalSettings();
  const { status } = useCustomerAuth();
  const authenticated = status === 'authenticated';
  const navigate = useNavigate();
  const view = useCartView();
  const query = useCart({ query: { queryKey: cartQueryKey(), enabled: authenticated } });
  const checkout = useCheckout();
  const applyDiscount = useApplyCartDiscount();
  const removeDiscount = useRemoveCartDiscount();
  const updateLine = useUpdateCartLineItem();
  const removeLine = useRemoveCartLineItem();
  const { toast } = useToast();
  const [code, setCode] = useState('');

  const cart = body<Cart>(query);
  const pricing = cart?.pricing as CartPricing | null | undefined;
  const currency = settings.currency;

  const onCheckout = async () => {
    try {
      const result = await checkout.mutateAsync();
      const payload = responseData<CheckoutResult>(result);
      const redirect = payload?.redirect_url;
      if (redirect) {
        onRedirect(redirect);
      } else {
        toast({ title: 'Order placed', variant: 'success' });
        await query.refetch();
        navigate('/orders');
      }
    } catch (error) {
      toast({ title: friendlyError(errorCode(error), errorMessage(error)), variant: 'danger' });
    }
  };

  const onApply = async () => {
    if (!code.trim()) return;
    try {
      await applyDiscount.mutateAsync({ data: { code: code.trim() } });
      toast({ title: 'Discount applied', variant: 'success' });
      setCode('');
    } catch (error) {
      toast({ title: friendlyError(errorCode(error), errorMessage(error)), variant: 'danger' });
    }
  };

  const loading = status === 'loading' || (authenticated && query.isLoading);
  const visibleLines = view.lines.filter((line) => !line.pending);

  return (
    <div className="flex flex-col gap-4">
      <PageHeader title="Cart" description="Review your items before checkout." />

      <QueryState
        loading={loading}
        error={authenticated && query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {visibleLines.length === 0 && view.pendingLines.length === 0 ? (
          <EmptyState
            title="Your cart is empty"
            description="Add packages, drop-ins or merchandise to continue."
            action={
              <Button asChild>
                <Link to="/schedule">Browse schedule</Link>
              </Button>
            }
          />
        ) : (
          <>
            {visibleLines.length > 0 ? (
              <ul className="flex flex-col divide-y divide-border rounded-lg border border-border">
                {visibleLines.map((line) => (
                  <li
                    key={line.id}
                    className="flex flex-wrap items-center justify-between gap-3 p-3"
                  >
                    <div className="flex flex-col">
                      <span className="font-medium">{line.title}</span>
                      <span className="text-xs capitalize text-muted-foreground">
                        {line.subtitle ?? line.type.replace(/_/g, ' ')}
                        {line.pending ? ' · choose a player below' : ''}
                      </span>
                    </div>
                    <div className="flex items-center gap-3">
                      <div className="flex items-center gap-1">
                        <Button
                          variant="outline"
                          size="sm"
                          aria-label="Decrease quantity"
                          onClick={() => {
                            if (line.pending) return;
                            const next = Math.max(1, line.quantity - 1);
                            if (authenticated) {
                              void updateLine
                                .mutateAsync({ id: line.id, data: { quantity: next } })
                                .catch((error) =>
                                  toast({ title: errorMessage(error), variant: 'danger' }),
                                );
                            } else if (line.guestId) {
                              updateGuestQuantity(line.guestId, next);
                            }
                          }}
                        >
                          −
                        </Button>
                        <span className="w-6 text-center text-sm">{line.quantity}</span>
                        <Button
                          variant="outline"
                          size="sm"
                          aria-label="Increase quantity"
                          onClick={() => {
                            if (line.pending) return;
                            const next = line.quantity + 1;
                            if (authenticated) {
                              void updateLine
                                .mutateAsync({ id: line.id, data: { quantity: next } })
                                .catch((error) =>
                                  toast({ title: errorMessage(error), variant: 'danger' }),
                                );
                            } else if (line.guestId) {
                              updateGuestQuantity(line.guestId, next);
                            }
                          }}
                        >
                          +
                        </Button>
                      </div>
                      <MoneyDisplay amountMinor={line.lineTotalMinor} currency={currency} />
                      <Button
                        variant="ghost"
                        size="sm"
                        aria-label={`Remove ${line.title}`}
                        onClick={() => {
                          if (line.pending && line.guestId) {
                            removeGuestLine(line.guestId);
                            return;
                          }
                          if (authenticated) {
                            void removeLine
                              .mutateAsync({ id: line.id })
                              .catch((error) =>
                                toast({ title: errorMessage(error), variant: 'danger' }),
                              );
                          } else if (line.guestId) {
                            removeGuestLine(line.guestId);
                          }
                        }}
                      >
                        <Trash2 className="h-4 w-4" aria-hidden="true" />
                      </Button>
                    </div>
                  </li>
                ))}
              </ul>
            ) : null}

            {!authenticated ? (
              <Card>
                <CardContent className="flex flex-col gap-3 pt-4">
                  <dl className="flex flex-col gap-1 text-sm">
                    <div className="flex justify-between text-base font-semibold">
                      <dt>Subtotal</dt>
                      <dd>
                        <MoneyDisplay amountMinor={view.subtotalMinor} currency={currency} />
                      </dd>
                    </div>
                  </dl>
                  <p className="text-sm text-muted-foreground">
                    Sign in or create an account to check out. Your cart will be saved.
                  </p>
                  <div className="flex flex-wrap gap-2">
                    <Button asChild>
                      <Link to="/login" state={{ from: '/cart' }}>
                        Sign in to check out
                      </Link>
                    </Button>
                    <Button asChild variant="outline">
                      <Link to="/register" state={{ from: '/cart' }}>
                        Create an account
                      </Link>
                    </Button>
                  </div>
                </CardContent>
              </Card>
            ) : (
              <>
                {view.pendingLines.length > 0 ? (
                  <PendingDropIns lines={view.pendingLines} currency={currency} />
                ) : null}

                <Card>
                  <CardContent className="flex flex-col gap-4 pt-4">
                    <div className="flex flex-col gap-2">
                      <span className="text-sm font-medium">Discount code</span>
                      {cart?.discount_code ? (
                        <div className="flex items-center gap-2">
                          <Badge variant="success">{cart.discount_code}</Badge>
                          <Button
                            variant="ghost"
                            size="sm"
                            onClick={() =>
                              void removeDiscount
                                .mutateAsync()
                                .catch((error) =>
                                  toast({ title: errorMessage(error), variant: 'danger' }),
                                )
                            }
                          >
                            Remove
                          </Button>
                        </div>
                      ) : (
                        <div className="flex flex-wrap items-end gap-2">
                          <Input
                            aria-label="Discount code"
                            value={code}
                            onChange={(event) => setCode(event.target.value)}
                            placeholder="SUMMER10"
                            className="max-w-xs"
                          />
                          <Button
                            variant="outline"
                            onClick={() => void onApply()}
                            disabled={applyDiscount.isPending}
                          >
                            Apply
                          </Button>
                        </div>
                      )}
                    </div>

                    <dl className="flex flex-col gap-1 border-t border-border pt-3 text-sm">
                      <div className="flex justify-between">
                        <dt className="text-muted-foreground">Subtotal</dt>
                        <dd>
                          <MoneyDisplay amountMinor={pricing?.subtotal ?? 0} currency={currency} />
                        </dd>
                      </div>
                      {pricing && pricing.discount_total > 0 ? (
                        <div className="flex justify-between">
                          <dt className="text-muted-foreground">Discount</dt>
                          <dd>
                            −
                            <MoneyDisplay
                              amountMinor={pricing.discount_total}
                              currency={currency}
                            />
                          </dd>
                        </div>
                      ) : null}
                      <div className="flex justify-between">
                        <dt className="text-muted-foreground">Tax</dt>
                        <dd>
                          <MoneyDisplay amountMinor={pricing?.tax_total ?? 0} currency={currency} />
                        </dd>
                      </div>
                      <div className="flex justify-between text-base font-semibold">
                        <dt>Total</dt>
                        <dd>
                          <MoneyDisplay amountMinor={pricing?.total ?? 0} currency={currency} />
                        </dd>
                      </div>
                    </dl>

                    {view.pendingLines.length > 0 ? (
                      <p className="text-sm text-muted-foreground">
                        Add the drop-ins above before checking out.
                      </p>
                    ) : null}

                    <div>
                      <Button
                        onClick={() => void onCheckout()}
                        disabled={checkout.isPending || view.pendingLines.length > 0}
                      >
                        {checkout.isPending ? 'Starting checkout…' : 'Go to checkout'}
                      </Button>
                    </div>
                  </CardContent>
                </Card>
              </>
            )}
          </>
        )}
      </QueryState>
    </div>
  );
}

function PendingDropIns({ lines, currency }: { lines: GuestLine[]; currency: string }) {
  const playersQuery = usePlayers();
  const availablePlayers = listItems<PlayerResponse>(playersQuery);

  return (
    <Card className="border-primary/40 bg-primary/5">
      <CardContent className="flex flex-col gap-3 pt-4">
        <div>
          <h2 className="text-sm font-semibold">Drop-ins to confirm</h2>
          <p className="text-sm text-muted-foreground">
            Choose a player for each drop-in and add it to your cart.
          </p>
        </div>

        {playersQuery.isLoading ? (
          <p className="text-sm text-muted-foreground">Loading players…</p>
        ) : availablePlayers.length === 0 ? (
          <p className="text-sm text-muted-foreground">
            You need a player before you can add a drop-in.{' '}
            <Link className="text-primary hover:underline" to="/players">
              Add a player
            </Link>
            .
          </p>
        ) : (
          <ul className="flex flex-col divide-y divide-border">
            {lines.map((line) => (
              <PendingDropInRow
                key={line.id}
                line={line}
                players={availablePlayers}
                currency={currency}
              />
            ))}
          </ul>
        )}
      </CardContent>
    </Card>
  );
}

function PendingDropInRow({
  line,
  players,
  currency,
}: {
  line: GuestLine;
  players: PlayerResponse[];
  currency: string;
}) {
  const { toast } = useToast();
  const createBooking = useCreateBooking();
  const addToCart = useAddToCart();
  const [playerId, setPlayerId] = useState<string | undefined>(players[0]?.id);
  const [submitting, setSubmitting] = useState(false);

  const onAdd = async () => {
    if (!playerId) {
      toast({ title: 'Choose a player first', variant: 'danger' });
      return;
    }
    setSubmitting(true);
    try {
      const holdResult = await createBooking.mutateAsync({
        data: { player_id: playerId, session_id: line.ref_id, method: 'paid' },
      });
      const hold = responseData<{ id?: string }>(holdResult);
      if (!hold?.id) throw new Error('Could not hold this drop-in');
      await addToCart.mutateAsync({
        data: { type: 'drop_in', ref_id: hold.id, quantity: 1 },
      });
      removeGuestLine(line.id);
      toast({ title: 'Added to cart', variant: 'success' });
    } catch (error) {
      toast({ title: friendlyError(errorCode(error), errorMessage(error)), variant: 'danger' });
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <li className="flex flex-wrap items-center justify-between gap-3 py-3">
      <div className="flex flex-col">
        <span className="font-medium">{line.snapshot.title}</span>
        <span className="text-xs text-muted-foreground">
          {[line.snapshot.venueName, line.snapshot.startsAt].filter(Boolean).join(' · ') ||
            'Drop-in'}
        </span>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <div className="w-48">
          <PlayerSelect players={players} value={playerId} onChange={setPlayerId} />
        </div>
        {typeof line.snapshot.priceMinor === 'number' ? (
          <MoneyDisplay amountMinor={line.snapshot.priceMinor} currency={currency} />
        ) : null}
        <Button onClick={() => void onAdd()} disabled={submitting || !playerId}>
          {submitting ? 'Adding…' : 'Add to cart'}
        </Button>
      </div>
    </li>
  );
}
