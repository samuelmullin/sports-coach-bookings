import { useState } from 'react';
import { Controller, useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  FormField,
  Input,
  MoneyDisplay,
  MoneyInput,
  Select,
} from '@scb/ui';
import {
  useOfferings,
  useSimulatePolicy,
  type PolicySimulationResponse,
} from '../../api/endpoints';
import { errorMessage, listItems, responseData } from '../shared/api-utils';
import { useTenantSettings } from '../shared/useTenantSettings';

const schema = z.object({
  action: z.enum(['cancel', 'rebook', 'no_show', 'provider_cancel']),
  hours_before: z.coerce.number().min(0),
  payment_method: z.enum(['credits', 'paid']),
  amount_paid: z.number().nullable(),
  offering_id: z.string(),
});

type FormValues = z.infer<typeof schema>;

export function PolicySimulator({ policyId }: { policyId: string }) {
  const simulate = useSimulatePolicy();
  const offerings = listItems<{ id: string; name: string }>(useOfferings());
  const { currency } = useTenantSettings();
  const [outcome, setOutcome] = useState<PolicySimulationResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  const { register, control, handleSubmit, watch, setValue } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      action: 'cancel',
      hours_before: 12,
      payment_method: 'credits',
      amount_paid: 5000,
      offering_id: '',
    },
  });
  const paymentMethod = watch('payment_method');

  const onSubmit = handleSubmit(async (values) => {
    setError(null);
    try {
      const result = await simulate.mutateAsync({
        data: {
          policy_id: policyId,
          action: values.action,
          hours_before: values.hours_before,
          payment_method: values.payment_method,
          amount_paid: values.payment_method === 'paid' ? values.amount_paid : null,
          offering_id: values.offering_id || null,
          currency,
        },
      });
      setOutcome(responseData<PolicySimulationResponse>(result) ?? null);
    } catch (err) {
      setError(errorMessage(err));
    }
  });

  return (
    <Card>
      <CardHeader>
        <CardTitle>Simulator</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-4">
        <form className="grid gap-4 sm:grid-cols-2" onSubmit={onSubmit} noValidate>
          <FormField label="Action">
            <Controller
              control={control}
              name="action"
              render={({ field }) => (
                <Select
                  aria-label="Action"
                  value={field.value}
                  onValueChange={field.onChange}
                  options={[
                    { value: 'cancel', label: 'Customer cancels' },
                    { value: 'rebook', label: 'Customer rebooks' },
                    { value: 'no_show', label: 'No-show' },
                    { value: 'provider_cancel', label: 'Provider cancels' },
                  ]}
                />
              )}
            />
          </FormField>
          <FormField label="Hours before session">
            <Input type="number" {...register('hours_before')} />
          </FormField>
          <FormField label="Payment method">
            <Controller
              control={control}
              name="payment_method"
              render={({ field }) => (
                <Select
                  aria-label="Payment method"
                  value={field.value}
                  onValueChange={field.onChange}
                  options={[
                    { value: 'credits', label: 'Sessions' },
                    { value: 'paid', label: 'Paid' },
                  ]}
                />
              )}
            />
          </FormField>
          {paymentMethod === 'paid' ? (
            <FormField label="Amount paid">
              <Controller
                control={control}
                name="amount_paid"
                render={({ field }) => (
                  <MoneyInput currency={currency} value={field.value} onChange={field.onChange} />
                )}
              />
            </FormField>
          ) : null}
          <FormField label="Offering">
            <Select
              aria-label="Offering"
              value={watch('offering_id')}
              onValueChange={(value) => setValue('offering_id', value)}
              options={[
                { value: '', label: 'Any offering' },
                ...offerings.map((offering) => ({ value: offering.id, label: offering.name })),
              ]}
            />
          </FormField>
          <div className="sm:col-span-2">
            <Button type="submit" disabled={simulate.isPending}>
              Run simulation
            </Button>
          </div>
        </form>

        {error ? <p className="text-sm text-danger">{error}</p> : null}

        {outcome ? (
          <div
            className="rounded-md border border-border p-3 text-sm"
            data-testid="simulator-outcome"
          >
            <div className="flex items-center gap-2">
              <Badge variant={outcome.outcome.allowed ? 'success' : 'danger'}>
                {outcome.outcome.allowed ? 'Allowed' : 'Not allowed'}
              </Badge>
              {outcome.outcome.tier_matched != null ? (
                <span className="text-xs text-muted-foreground">
                  Matched tier: {outcome.outcome.tier_matched}h+
                </span>
              ) : null}
            </div>
            <p className="mt-2">
              Sessions: {outcome.outcome.credit_outcome ?? 'none'}
              {outcome.outcome.refund_amount ? (
                <>
                  {' · Refund: '}
                  <MoneyDisplay
                    amountMinor={outcome.outcome.refund_amount.amount}
                    currency={outcome.outcome.refund_amount.currency}
                  />
                </>
              ) : null}
            </p>
            {outcome.outcome.reason ? (
              <p className="text-muted-foreground">{outcome.outcome.reason}</p>
            ) : null}
          </div>
        ) : null}
      </CardContent>
    </Card>
  );
}
