import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { Button, RadioGroup, Splash } from '@scb/ui';
import { useCustomerAuth } from '../../auth/customer-auth';
import {
  useAcceptSessionInvitation,
  usePlayers,
  useSessionInvitation,
  type PlayerResponse,
} from '../../api/endpoints';
import { body, errorMessage, listItems, responseData } from '../../features/shared/api-utils';
import { PlayerSelect } from '../../features/shared/PlayerSelect';
import { PortalAuthLayout } from '../../layouts/PortalAuthLayout';
import { useAddToCart } from '../../features/cart/useCart';

export function AcceptSessionInvitePage() {
  const { token = '' } = useParams();
  const navigate = useNavigate();
  const { status } = useCustomerAuth();
  const inviteQuery = useSessionInvitation(token);
  const playersQuery = usePlayers({
    query: { queryKey: ['players', 'session-invite'], enabled: status === 'authenticated' },
  });
  const accept = useAcceptSessionInvitation();
  const addToCart = useAddToCart();
  const invite = body<Record<string, unknown>>(inviteQuery);
  const players = listItems<PlayerResponse>(playersQuery);
  const [playerId, setPlayerId] = useState<string | undefined>();
  const [method, setMethod] = useState<'credits' | 'paid'>('paid');
  const [failure, setFailure] = useState<string | null>(null);

  if (inviteQuery.isLoading) return <Splash label="Loading invitation…" />;

  if (!invite || inviteQuery.isError) {
    return (
      <PortalAuthLayout title="Invitation unavailable">
        This invitation could not be found.
      </PortalAuthLayout>
    );
  }

  if (status !== 'authenticated') {
    return (
      <PortalAuthLayout
        title="You're invited"
        subtitle="Sign in or create an account to choose a player."
      >
        <div className="flex gap-2">
          <Button asChild>
            <Link to="/login" state={{ from: `/session-invites/${token}` }}>
              Sign in
            </Link>
          </Button>
          <Button asChild variant="outline">
            <Link to="/register" state={{ from: `/session-invites/${token}` }}>
              Create account
            </Link>
          </Button>
        </div>
      </PortalAuthLayout>
    );
  }

  const organizerPays = invite.payment_mode === 'organizer';
  const submit = async () => {
    if (!playerId) return;
    setFailure(null);
    try {
      const result = await accept.mutateAsync({ token, data: { player_id: playerId, method } });
      const accepted = responseData<{ booking?: { id?: string } }>(result);
      if (!organizerPays && method === 'paid' && accepted?.booking?.id) {
        await addToCart.mutateAsync({
          data: { type: 'drop_in', ref_id: accepted.booking.id, quantity: 1 },
        });
      }
      navigate(organizerPays || method === 'credits' ? '/bookings' : '/cart', { replace: true });
    } catch (error) {
      setFailure(errorMessage(error));
    }
  };

  return (
    <PortalAuthLayout
      title="Accept session invitation"
      subtitle={
        organizerPays
          ? 'The organizer is covering your space.'
          : 'Choose your player and payment method.'
      }
    >
      <div className="flex flex-col gap-4">
        <PlayerSelect players={players} value={playerId} onChange={setPlayerId} />
        {!organizerPays ? (
          <RadioGroup
            label="Payment method"
            value={method}
            onValueChange={(value) => setMethod(value as 'credits' | 'paid')}
            options={[
              { value: 'paid', label: 'Pay at checkout' },
              { value: 'credits', label: 'Use session credits' },
            ]}
          />
        ) : null}
        {failure ? (
          <p role="alert" className="text-sm text-danger">
            {failure}
          </p>
        ) : null}
        <Button
          onClick={() => void submit()}
          disabled={!playerId || accept.isPending || addToCart.isPending}
        >
          {accept.isPending ? 'Accepting…' : 'Accept invitation'}
        </Button>
      </div>
    </PortalAuthLayout>
  );
}
