import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useEffect } from 'react';
import {
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  FormField,
  Input,
  Switch,
  useToast,
} from '@scb/ui';
import { useNotificationPreferences, useUpdateNotificationPreferences } from '../../api/extras';
import { errorMessage } from '../shared/api-utils';

const schema = z.object({
  reminder_lead_hours: z.coerce.number().min(1, 'At least 1 hour').max(336, 'At most 14 days'),
  reminder_email: z.boolean(),
  reminder_sms: z.boolean(),
});

type FormValues = z.infer<typeof schema>;

export function ReminderTimingForm() {
  const query = useNotificationPreferences();
  const update = useUpdateNotificationPreferences();
  const { toast } = useToast();
  const { register, handleSubmit, reset, watch, setValue } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { reminder_lead_hours: 24, reminder_email: true, reminder_sms: false },
  });

  useEffect(() => {
    if (query.data) reset(query.data);
  }, [query.data, reset]);

  const onSubmit = handleSubmit(async (values) => {
    try {
      await update.mutateAsync(values);
      toast({ title: 'Reminder timing saved', variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  return (
    <Card>
      <CardHeader>
        <CardTitle>Reminder timing</CardTitle>
      </CardHeader>
      <CardContent>
        <p className="mb-4 rounded-md bg-muted p-2 text-xs text-muted-foreground">
          Mock-backed: reminder preferences are not yet part of the staff API.
        </p>
        <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
          <FormField
            label="Send reminders (hours before session)"
            help="Customers with an upcoming booking are reminded this many hours ahead."
          >
            <Input type="number" min={1} {...register('reminder_lead_hours')} />
          </FormField>
          <div className="flex flex-col gap-3">
            <Switch
              label="Email reminders"
              checked={watch('reminder_email')}
              onCheckedChange={(checked) => setValue('reminder_email', checked)}
            />
            <Switch
              label="SMS reminders"
              checked={watch('reminder_sms')}
              onCheckedChange={(checked) => setValue('reminder_sms', checked)}
            />
          </div>
          <div className="flex justify-end">
            <Button type="submit" disabled={update.isPending}>
              Save reminders
            </Button>
          </div>
        </form>
      </CardContent>
    </Card>
  );
}
