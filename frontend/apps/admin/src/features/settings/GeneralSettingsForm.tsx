import { zodResolver } from '@hookform/resolvers/zod';
import { Controller, useForm } from 'react-hook-form';
import { z } from 'zod';
import { useEffect } from 'react';
import { applyApiFieldErrors } from '@scb/api-client';
import {
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  FormField,
  Input,
  Select,
  useToast,
} from '@scb/ui';
import { useSettings, useUpdateSettings, type TenantSettings } from '../../api/endpoints';
import { body, errorMessage } from '../shared/api-utils';
import { CURRENCIES, TIMEZONES } from './constants';

const schema = z.object({
  name: z.string().min(1, 'Name is required'),
  contact_email: z.string().email('Enter a valid email').or(z.literal('')),
  timezone: z.string().min(1, 'Timezone is required'),
  currency: z.string().min(1, 'Currency is required'),
});

type FormValues = z.infer<typeof schema>;

export function GeneralSettingsForm() {
  const settingsQuery = useSettings();
  const update = useUpdateSettings();
  const { toast } = useToast();
  const settings = body<TenantSettings>(settingsQuery);
  const currencyLocked = settings?.currency_locked ?? false;

  const {
    register,
    control,
    handleSubmit,
    reset,
    setError,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { name: '', contact_email: '', timezone: 'America/Toronto', currency: 'CAD' },
  });

  useEffect(() => {
    if (settings?.tenant) {
      reset({
        name: settings.tenant.name ?? '',
        contact_email: settings.tenant.contact_email ?? '',
        timezone: settings.tenant.timezone ?? 'America/Toronto',
        currency: settings.tenant.currency ?? 'CAD',
      });
    }
  }, [settings, reset]);

  const onSubmit = handleSubmit(async (values) => {
    try {
      await update.mutateAsync({ data: values });
      toast({ title: 'Settings saved', variant: 'success' });
    } catch (error) {
      const applied = applyApiFieldErrors(error, { setError, fallbackField: 'name' });
      if (!applied.handled) {
        toast({ title: errorMessage(error), variant: 'danger' });
      }
    }
  });

  if (settingsQuery.isLoading) {
    return <p className="text-sm text-muted-foreground">Loading settings…</p>;
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Business details</CardTitle>
      </CardHeader>
      <CardContent>
        <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
          <FormField label="Business name" required error={errors.name?.message}>
            <Input {...register('name')} />
          </FormField>
          <FormField label="Contact email" error={errors.contact_email?.message}>
            <Input type="email" {...register('contact_email')} />
          </FormField>
          <div className="grid gap-4 sm:grid-cols-2">
            <Controller
              control={control}
              name="timezone"
              render={({ field }) => (
                <FormField
                  label="Timezone"
                  required
                  help="All session times are shown in this timezone."
                  error={errors.timezone?.message}
                >
                  <Select
                    aria-label="Timezone"
                    options={TIMEZONES.map((zone) => ({ value: zone, label: zone }))}
                    value={field.value}
                    onValueChange={field.onChange}
                  />
                </FormField>
              )}
            />
            <Controller
              control={control}
              name="currency"
              render={({ field }) => (
                <FormField
                  label="Currency"
                  required
                  help={
                    currencyLocked
                      ? 'Currency is locked because orders already exist.'
                      : 'Used for all prices in your catalog.'
                  }
                  error={errors.currency?.message}
                >
                  <Select
                    aria-label="Currency"
                    disabled={currencyLocked}
                    options={CURRENCIES.map((c) => ({ value: c.value, label: c.label }))}
                    value={field.value}
                    onValueChange={field.onChange}
                  />
                </FormField>
              )}
            />
          </div>
          <div className="flex justify-end">
            <Button type="submit" disabled={isSubmitting || update.isPending}>
              {update.isPending ? 'Saving…' : 'Save settings'}
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  );
}
