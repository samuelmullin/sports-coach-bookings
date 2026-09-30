import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { applyApiFieldErrors } from '@scb/api-client';
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  ConfirmDialog,
  FormField,
  Input,
  useToast,
} from '@scb/ui';
import {
  useCustomer,
  useDeactivateCustomer,
  useReactivateCustomer,
  useResetCustomerPassword,
  useUpdateCustomer,
} from '../../api/endpoints';
import { body, errorMessage } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';

const schema = z.object({
  first_name: z.string(),
  last_name: z.string(),
  phone: z.string(),
});

type FormValues = z.infer<typeof schema>;

interface CustomerShape {
  id?: string;
  first_name?: string;
  last_name?: string;
  email?: string;
  phone?: string | null;
  active?: boolean;
  confirmed?: boolean;
}

export function CustomerDetailPage() {
  const { customerId = '' } = useParams();
  const query = useCustomer(customerId);
  const customer = body<CustomerShape>(query);
  const update = useUpdateCustomer();
  const deactivate = useDeactivateCustomer();
  const reactivate = useReactivateCustomer();
  const resetPassword = useResetCustomerPassword();
  const { toast } = useToast();
  const [confirmDeactivate, setConfirmDeactivate] = useState(false);

  const { register, handleSubmit, reset, setError } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { first_name: '', last_name: '', phone: '' },
  });

  useEffect(() => {
    if (customer) {
      reset({
        first_name: customer.first_name ?? '',
        last_name: customer.last_name ?? '',
        phone: customer.phone ?? '',
      });
    }
  }, [customer, reset]);

  const onSubmit = handleSubmit(async (values) => {
    try {
      await update.mutateAsync({
        id: customerId,
        data: { ...values, phone: values.phone || null },
      });
      toast({ title: 'Customer updated', variant: 'success' });
    } catch (error) {
      const applied = applyApiFieldErrors(error, { setError, fallbackField: 'first_name' });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title={[customer?.first_name, customer?.last_name].filter(Boolean).join(' ') || 'Customer'}
        description={customer?.email}
        actions={
          <div className="flex flex-wrap gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() =>
                void resetPassword
                  .mutateAsync({ id: customerId })
                  .then(() => toast({ title: 'Password reset email sent', variant: 'success' }))
                  .catch((error) => toast({ title: errorMessage(error), variant: 'danger' }))
              }
            >
              Send password reset
            </Button>
            {customer?.active ? (
              <Button variant="danger" size="sm" onClick={() => setConfirmDeactivate(true)}>
                Deactivate
              </Button>
            ) : (
              <Button
                variant="outline"
                size="sm"
                onClick={() =>
                  void reactivate
                    .mutateAsync({ id: customerId })
                    .then(() => {
                      toast({ title: 'Customer reactivated', variant: 'success' });
                      void query.refetch();
                    })
                    .catch((error) => toast({ title: errorMessage(error), variant: 'danger' }))
                }
              >
                Reactivate
              </Button>
            )}
          </div>
        }
      />

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        <div className="flex gap-2">
          <Badge variant={customer?.active ? 'success' : 'outline'}>
            {customer?.active ? 'Active' : 'Inactive'}
          </Badge>
          <Badge variant={customer?.confirmed ? 'success' : 'warning'}>
            {customer?.confirmed ? 'Confirmed' : 'Unconfirmed'}
          </Badge>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>Profile</CardTitle>
          </CardHeader>
          <CardContent>
            <form className="grid gap-4 sm:grid-cols-2" onSubmit={onSubmit} noValidate>
              <FormField label="First name">
                <Input {...register('first_name')} />
              </FormField>
              <FormField label="Last name">
                <Input {...register('last_name')} />
              </FormField>
              <FormField label="Phone">
                <Input {...register('phone')} />
              </FormField>
              <div className="flex items-end">
                <Button type="submit" disabled={update.isPending}>
                  Save
                </Button>
              </div>
            </form>
          </CardContent>
        </Card>
      </QueryState>

      <ConfirmDialog
        open={confirmDeactivate}
        onOpenChange={setConfirmDeactivate}
        title="Deactivate customer?"
        description="They will not be able to sign in or make new bookings. Existing bookings are unaffected."
        confirmLabel="Deactivate"
        destructive
        loading={deactivate.isPending}
        onConfirm={() => {
          void deactivate
            .mutateAsync({ id: customerId })
            .then(() => {
              toast({ title: 'Customer deactivated', variant: 'success' });
              void query.refetch();
            })
            .catch((error) => toast({ title: errorMessage(error), variant: 'danger' }))
            .finally(() => setConfirmDeactivate(false));
        }}
      />
    </div>
  );
}
