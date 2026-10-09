import { useEffect, useState } from 'react';
import { useNavigate } from 'react-router-dom';
import { useQueryClient } from '@tanstack/react-query';
import { Button, FormField, Input, Modal, RadioGroup, useToast } from '@scb/ui';
import {
  useInvitationPartners,
  useInviteToSession,
  type InvitationPartner,
} from '../../api/endpoints';
import { errorMessage, listItems, responseData } from '../shared/api-utils';
import { useAddToCart } from '../cart/useCart';

export function InviteSessionDialog({
  sessionId,
  open,
  onOpenChange,
}: {
  sessionId: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const partnersQuery = useInvitationPartners();
  const invite = useInviteToSession();
  const addToCart = useAddToCart();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const partners = listItems<InvitationPartner>(partnersQuery);
  const [email, setEmail] = useState('');
  const [paymentMode, setPaymentMode] = useState<'split' | 'organizer'>('split');
  const [method, setMethod] = useState<'credits' | 'paid'>('paid');

  useEffect(() => {
    if (!open) setEmail('');
  }, [open]);

  const submit = async () => {
    try {
      const result = await invite.mutateAsync({
        sessionId,
        data: {
          email,
          payment_mode: paymentMode,
          ...(paymentMode === 'organizer' ? { method } : {}),
        },
      });
      const body = responseData<{ booking?: { id?: string } | null }>(result);
      await queryClient.invalidateQueries({ queryKey: ['/api/portal/bookings/invitations'] });
      if (paymentMode === 'organizer' && method === 'paid' && body?.booking?.id) {
        await addToCart.mutateAsync({
          data: { type: 'drop_in', ref_id: body.booking.id, quantity: 1 },
        });
        toast({ title: 'Guest space held—complete payment in your cart', variant: 'success' });
        onOpenChange(false);
        navigate('/cart');
        return;
      }
      toast({ title: 'Invitation sent', variant: 'success' });
      onOpenChange(false);
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  return (
    <Modal
      open={open}
      onOpenChange={onOpenChange}
      title="Invite another player"
      description="Choose someone you've played with before or enter an email address."
      footer={
        <>
          <Button variant="outline" onClick={() => onOpenChange(false)}>
            Cancel
          </Button>
          <Button
            onClick={() => void submit()}
            disabled={!email || invite.isPending || addToCart.isPending}
          >
            {invite.isPending ? 'Sending…' : 'Send invitation'}
          </Button>
        </>
      }
    >
      <div className="flex flex-col gap-4">
        {partners.length > 0 ? (
          <div className="flex flex-col gap-2">
            <p className="text-sm font-medium">Previous partners</p>
            <div className="flex flex-wrap gap-2">
              {partners.map((partner) => {
                const partnerEmail = String(partner.email ?? '');
                return (
                  <Button
                    key={partnerEmail}
                    size="sm"
                    variant={email === partnerEmail ? 'primary' : 'outline'}
                    onClick={() => setEmail(partnerEmail)}
                  >
                    {partnerEmail}
                  </Button>
                );
              })}
            </div>
          </div>
        ) : null}
        <FormField label="Invite by email">
          <Input
            type="email"
            autoComplete="email"
            value={email}
            onChange={(event) => setEmail(event.target.value)}
          />
        </FormField>
        <RadioGroup
          label="Who pays?"
          value={paymentMode}
          onValueChange={(value) => setPaymentMode(value as 'split' | 'organizer')}
          options={[
            { value: 'split', label: 'They pay their own share' },
            { value: 'organizer', label: 'I will pay for their space' },
          ]}
        />
        {paymentMode === 'organizer' ? (
          <RadioGroup
            label="Payment method"
            value={method}
            onValueChange={(value) => setMethod(value as 'credits' | 'paid')}
            options={[
              { value: 'paid', label: 'Pay at checkout' },
              { value: 'credits', label: 'Use session credits' },
            ]}
          />
        ) : (
          <p className="text-xs text-muted-foreground">
            Their space is reserved temporarily. Near the session start, temporary reservations
            close, but you can still purchase a guest space yourself.
          </p>
        )}
      </div>
    </Modal>
  );
}
