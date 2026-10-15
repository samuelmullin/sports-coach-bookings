import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { Download, Trash2 } from 'lucide-react';
import { ApiError } from '@scb/api-client';
import { Button, FormField, Input, Modal, useToast } from '@scb/ui';
import { householdExportUrl, useEraseHousehold } from '../../api/endpoints';
import { errorMessage } from '../shared/api-utils';

const schema = z.object({
  password: z.string().min(1, 'Enter your password'),
  // `: boolean` stops TS inferring a type predicate that would narrow the field to 'ERASE'.
  confirm: z.string().refine((value): boolean => value === 'ERASE', 'Type ERASE to confirm'),
});

type FormValues = z.infer<typeof schema>;

const BLOCKERS: Record<string, string> = {
  upcoming_bookings: 'You have upcoming bookings. Cancel them first.',
  pending_orders: 'You have an unpaid order. Finish or cancel it first.',
};

function blockerMessages(error: ApiError): string[] {
  const details = error.details as { reasons?: unknown } | undefined;
  const reasons = Array.isArray(details?.reasons) ? (details.reasons as string[]) : [];
  return reasons.map((reason) => BLOCKERS[reason] ?? reason);
}

/** PIPEDA: download everything held about the household, or erase it. */
export function PrivacySection() {
  const [open, setOpen] = useState(false);
  const [blockers, setBlockers] = useState<string[]>([]);
  const erase = useEraseHousehold();
  const { toast } = useToast();

  const {
    register,
    handleSubmit,
    reset,
    setError,
    formState: { errors },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { password: '', confirm: '' },
  });

  const close = (next: boolean) => {
    setOpen(next);
    if (!next) {
      reset();
      setBlockers([]);
    }
  };

  const onSubmit = handleSubmit(async (values) => {
    setBlockers([]);
    try {
      await erase.mutateAsync({ data: { password: values.password, confirm: 'ERASE' } });
      // The session ended with the erasure; leave the app.
      window.location.assign('/login');
    } catch (error) {
      if (error instanceof ApiError && error.code === 'invalid_password') {
        setError('password', { type: 'server', message: 'That password is incorrect.' });
      } else if (error instanceof ApiError && error.code === 'erasure_blocked') {
        setBlockers(blockerMessages(error));
      } else if (error instanceof ApiError && error.code === 'forbidden') {
        toast({
          title: 'Only the primary account holder can delete the household.',
          variant: 'danger',
        });
      } else {
        toast({ title: errorMessage(error), variant: 'danger' });
      }
    }
  });

  return (
    <div className="flex max-w-xl flex-col gap-8">
      <section className="flex flex-col gap-2" aria-labelledby="export-heading">
        <h2 id="export-heading" className="text-base font-semibold">
          Download your data
        </h2>
        <p className="text-sm text-muted-foreground">
          A copy of everything we hold about your household — accounts, players (including medical
          information), waivers, bookings, sessions and orders — as a JSON file.
        </p>
        <div>
          <Button asChild variant="outline">
            <a href={householdExportUrl()} download="household-data.json">
              <Download className="h-4 w-4" aria-hidden="true" /> Download my data
            </a>
          </Button>
        </div>
      </section>

      <section className="flex flex-col gap-2" aria-labelledby="erase-heading">
        <h2 id="erase-heading" className="text-base font-semibold">
          Delete your account
        </h2>
        <p className="text-sm text-muted-foreground">
          Permanently deletes your players and their medical information, and closes every account
          in your household. Receipts and payment records are kept without your personal details.
          Unused sessions are forfeited. This cannot be undone.
        </p>
        <div>
          <Button variant="danger" onClick={() => setOpen(true)}>
            <Trash2 className="h-4 w-4" aria-hidden="true" /> Delete my account
          </Button>
        </div>
      </section>

      <Modal
        open={open}
        onOpenChange={close}
        title="Delete your account?"
        description="Only the primary account holder can do this. It is permanent."
      >
        <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
          {blockers.length > 0 ? (
            <div
              role="alert"
              className="rounded-md border border-danger/40 bg-danger/10 p-3 text-sm"
            >
              <p className="font-medium">We can't delete your account yet:</p>
              <ul className="mt-1 list-disc pl-5">
                {blockers.map((message) => (
                  <li key={message}>{message}</li>
                ))}
              </ul>
            </div>
          ) : null}
          <FormField label="Your password" required error={errors.password?.message}>
            <Input type="password" autoComplete="current-password" {...register('password')} />
          </FormField>
          <FormField label="Type ERASE to confirm" required error={errors.confirm?.message}>
            <Input autoComplete="off" {...register('confirm')} />
          </FormField>
          <div className="flex justify-end gap-2">
            <Button type="button" variant="outline" onClick={() => close(false)}>
              Keep my account
            </Button>
            <Button type="submit" variant="danger" disabled={erase.isPending}>
              {erase.isPending ? 'Deleting…' : 'Permanently delete'}
            </Button>
          </div>
        </form>
      </Modal>
    </div>
  );
}
