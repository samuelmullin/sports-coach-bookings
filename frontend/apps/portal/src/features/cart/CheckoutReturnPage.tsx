import { useEffect, useRef } from 'react';
import { Link, useNavigate, useSearchParams } from 'react-router-dom';
import { CheckCircle2, Clock, XCircle } from 'lucide-react';
import { Button, Card, CardContent, MoneyDisplay, useToast } from '@scb/ui';
import { useOrder, orderQueryKey, type OrderDetail } from '../../api/endpoints';
import { body, errorCode, errorMessage } from '../shared/api-utils';
import { friendlyError } from '../shared/errors';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { usePortalSettings } from '../shared/extras';
import { useOptionalReservation } from '../reservations/ReservationProvider';

const TERMINAL = new Set(['paid', 'expired', 'cancelled', 'refunded', 'partially_refunded']);

export function CheckoutReturnPage() {
  const [searchParams] = useSearchParams();
  const orderId = searchParams.get('order_id') ?? searchParams.get('orderId') ?? '';
  const settings = usePortalSettings();
  const navigate = useNavigate();
  const { toast } = useToast();
  const reservationContext = useOptionalReservation();
  const reservation = reservationContext?.reservation ?? null;
  const reservationStatus = reservationContext?.status;
  const convert = reservationContext?.convert;
  const convertedRef = useRef(false);
  const assignments = reservation?.assignments;

  const query = useOrder(orderId, {
    query: {
      queryKey: orderQueryKey(orderId),
      enabled: Boolean(orderId),
      retry: false,
      refetchInterval: (queryResult) => {
        const status = (queryResult.state.data as { data?: OrderDetail } | undefined)?.data?.status;
        if (!status || TERMINAL.has(status)) return false;
        return 2000;
      },
    },
  });

  const order = body<OrderDetail>(query);
  const status = order?.status;
  const currency = order?.currency ?? settings.currency;

  // Deferred pack conversion: the guest reserved sessions, bought a pack, and
  // the order is now paid. Convert using the assignments saved at checkout.
  useEffect(() => {
    if (status !== 'paid' || !convert) return;
    if (!reservation || reservationStatus !== 'active' || !assignments?.length) return;
    if (convertedRef.current) return;
    convertedRef.current = true;
    void (async () => {
      try {
        await convert(assignments);
        toast({ title: 'Booking confirmed', variant: 'success' });
        navigate('/bookings', { replace: true });
      } catch (error) {
        convertedRef.current = false;
        toast({
          title: friendlyError(errorCode(error), errorMessage(error)),
          variant: 'danger',
        });
      }
    })();
  }, [status, reservation, reservationStatus, assignments, convert, toast, navigate]);

  return (
    <div className="flex flex-col gap-4">
      <PageHeader title="Order status" />

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {!orderId ? (
          <p className="text-sm text-muted-foreground">No order was specified.</p>
        ) : !order ? (
          <p className="text-sm text-muted-foreground">Loading your order…</p>
        ) : (
          <Card>
            <CardContent className="flex flex-col items-center gap-3 pt-6 text-center">
              {status === 'paid' ? (
                <CheckCircle2 className="h-12 w-12 text-green-600" aria-hidden="true" />
              ) : status === 'expired' || status === 'cancelled' ? (
                <XCircle className="h-12 w-12 text-danger" aria-hidden="true" />
              ) : (
                <Clock className="h-12 w-12 text-amber-600" aria-hidden="true" />
              )}

              <h2 className="text-lg font-semibold">
                {status === 'paid'
                  ? 'Payment complete'
                  : status === 'expired'
                    ? 'Checkout expired'
                    : status === 'cancelled'
                      ? 'Order cancelled'
                      : 'Waiting for payment confirmation…'}
              </h2>

              <p className="text-sm text-muted-foreground">
                Order {order.number} · {order.status.replace(/_/g, ' ')}
              </p>
              <MoneyDisplay
                amountMinor={order.total}
                currency={currency}
                className="text-xl font-semibold"
              />

              <div className="flex flex-wrap justify-center gap-2 pt-2">
                {status === 'paid' ? (
                  <>
                    <Button asChild>
                      <Link to={`/orders/${order.id}`}>View receipt</Link>
                    </Button>
                    <Button asChild variant="outline">
                      <Link to="/bookings">My bookings</Link>
                    </Button>
                  </>
                ) : status === 'pending_payment' ? (
                  <Button variant="outline" onClick={() => void query.refetch()}>
                    Check again
                  </Button>
                ) : (
                  <Button asChild>
                    <Link to="/cart">Back to cart</Link>
                  </Button>
                )}
              </div>
            </CardContent>
          </Card>
        )}
      </QueryState>
    </div>
  );
}
