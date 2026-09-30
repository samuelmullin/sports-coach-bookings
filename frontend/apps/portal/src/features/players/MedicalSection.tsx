import { useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { Lock } from 'lucide-react';
import { applyApiFieldErrors } from '@scb/api-client';
import { Button, Card, CardContent, FormField, Textarea, useToast } from '@scb/ui';
import {
  playerMedicalQueryKey,
  usePlayerMedical,
  useUpdatePlayerMedical,
  type MedicalInfoResponse,
} from '../../api/endpoints';
import { body, errorMessage } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';

const schema = z.object({
  allergies: z.string().optional(),
  conditions: z.string().optional(),
  medications: z.string().optional(),
  notes: z.string().optional(),
});
type FormValues = z.infer<typeof schema>;

export function MedicalSection({ playerId }: { playerId: string }) {
  const query = usePlayerMedical(playerId);
  const mutation = useUpdatePlayerMedical();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const medical = body<MedicalInfoResponse>(query);

  const {
    register,
    handleSubmit,
    reset,
    setError,
    formState: { errors },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { allergies: '', conditions: '', medications: '', notes: '' },
  });

  useEffect(() => {
    if (medical) {
      reset({
        allergies: medical.allergies ?? '',
        conditions: medical.conditions ?? '',
        medications: medical.medications ?? '',
        notes: medical.notes ?? '',
      });
    }
  }, [medical, reset]);

  const onSubmit = handleSubmit(async (values) => {
    try {
      await mutation.mutateAsync({
        id: playerId,
        data: {
          allergies: values.allergies || null,
          conditions: values.conditions || null,
          medications: values.medications || null,
          notes: values.notes || null,
        },
      });
      await queryClient.invalidateQueries({ queryKey: playerMedicalQueryKey(playerId) });
      toast({ title: 'Medical information saved', variant: 'success' });
    } catch (error) {
      const applied = applyApiFieldErrors(error, { setError, fallbackField: 'notes' });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  return (
    <QueryState
      loading={query.isLoading}
      error={query.isError ? errorMessage(query.error) : undefined}
      onRetry={() => void query.refetch()}
    >
      <Card>
        <CardContent className="flex flex-col gap-4 pt-4">
          <p className="flex items-start gap-2 rounded-md bg-muted p-3 text-xs text-muted-foreground">
            <Lock className="mt-0.5 h-4 w-4 shrink-0" aria-hidden="true" />
            <span>
              This information is private. It is only visible to the household adults and to club
              staff who need it for the player's safety. It never appears in lists or booking
              screens.
            </span>
          </p>
          <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
            <FormField label="Allergies" error={errors.allergies?.message}>
              <Textarea rows={2} {...register('allergies')} />
            </FormField>
            <FormField label="Medical conditions" error={errors.conditions?.message}>
              <Textarea rows={2} {...register('conditions')} />
            </FormField>
            <FormField label="Medications" error={errors.medications?.message}>
              <Textarea rows={2} {...register('medications')} />
            </FormField>
            <FormField label="Other notes" error={errors.notes?.message}>
              <Textarea rows={2} {...register('notes')} />
            </FormField>
            <div>
              <Button type="submit" disabled={mutation.isPending}>
                {mutation.isPending ? 'Saving…' : 'Save medical information'}
              </Button>
            </div>
          </form>
        </CardContent>
      </Card>
    </QueryState>
  );
}
