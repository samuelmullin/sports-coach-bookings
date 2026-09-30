import { useEffect } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { applyApiFieldErrors } from '@scb/api-client';
import { Button, Checkbox, FormField, Input, Select, Textarea, useToast } from '@scb/ui';
import {
  playerQueryKey,
  playersQueryKey,
  usePositionOptions,
  useUpdatePlayer,
  useUpdatePlayerProfile,
  type PlayerProfileResponse,
  type PlayerResponse,
  type PositionOptionResponse,
} from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';

const basicsSchema = z.object({
  first_name: z.string().min(1, 'First name is required'),
  last_name: z.string().min(1, 'Last name is required'),
  date_of_birth: z.string().min(1, 'Date of birth is required'),
  preferred_name: z.string().optional(),
});
type BasicsValues = z.infer<typeof basicsSchema>;

export function PlayerBasicsForm({ player }: { player: PlayerResponse }) {
  const mutation = useUpdatePlayer();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const {
    register,
    handleSubmit,
    reset,
    setError,
    formState: { errors },
  } = useForm<BasicsValues>({
    resolver: zodResolver(basicsSchema),
    defaultValues: {
      first_name: '',
      last_name: '',
      date_of_birth: '',
      preferred_name: '',
    },
  });

  useEffect(() => {
    reset({
      first_name: player.first_name,
      last_name: player.last_name,
      date_of_birth: player.date_of_birth,
      preferred_name: player.preferred_name ?? '',
    });
  }, [player, reset]);

  const onSubmit = handleSubmit(async (values) => {
    try {
      await mutation.mutateAsync({
        id: player.id,
        data: {
          first_name: values.first_name,
          last_name: values.last_name,
          date_of_birth: values.date_of_birth,
          preferred_name: values.preferred_name || null,
        },
      });
      await queryClient.invalidateQueries({ queryKey: playersQueryKey() });
      await queryClient.invalidateQueries({ queryKey: playerQueryKey(player.id) });
      toast({ title: 'Player updated', variant: 'success' });
    } catch (error) {
      const applied = applyApiFieldErrors(error, {
        setError,
        fallbackField: 'first_name',
      });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  return (
    <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
      <FormField label="First name" required error={errors.first_name?.message}>
        <Input {...register('first_name')} />
      </FormField>
      <FormField label="Last name" required error={errors.last_name?.message}>
        <Input {...register('last_name')} />
      </FormField>
      <FormField label="Date of birth" required error={errors.date_of_birth?.message}>
        <Input type="date" {...register('date_of_birth')} />
      </FormField>
      <FormField label="Preferred name" error={errors.preferred_name?.message}>
        <Input {...register('preferred_name')} />
      </FormField>
      <div>
        <Button type="submit" disabled={mutation.isPending}>
          {mutation.isPending ? 'Saving…' : 'Save'}
        </Button>
      </div>
    </form>
  );
}

const profileSchema = z.object({
  home_club: z.string().optional(),
  team: z.string().optional(),
  dominant_foot: z.string().optional(),
  preferred_positions: z.array(z.string()),
  goals: z.string().optional(),
  interests: z.string().optional(),
  notes_from_family: z.string().optional(),
});
type ProfileValues = z.infer<typeof profileSchema>;

export function PlayerProfileForm({
  player,
  profile,
}: {
  player: PlayerResponse;
  profile?: PlayerProfileResponse;
}) {
  const mutation = useUpdatePlayerProfile();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const positions = listItems<PositionOptionResponse>(usePositionOptions());

  const {
    register,
    handleSubmit,
    reset,
    setError,
    setValue,
    watch,
    formState: { errors },
  } = useForm<ProfileValues>({
    resolver: zodResolver(profileSchema),
    defaultValues: {
      home_club: '',
      team: '',
      dominant_foot: '',
      preferred_positions: [],
      goals: '',
      interests: '',
      notes_from_family: '',
    },
  });

  useEffect(() => {
    reset({
      home_club: profile?.home_club ?? '',
      team: profile?.team ?? '',
      dominant_foot: profile?.dominant_foot ?? '',
      preferred_positions: profile?.preferred_positions ?? [],
      goals: profile?.goals ?? '',
      interests: (profile?.interests ?? []).join(', '),
      notes_from_family: profile?.notes_from_family ?? '',
    });
  }, [profile, reset]);

  const selected = watch('preferred_positions');

  const onSubmit = handleSubmit(async (values) => {
    try {
      await mutation.mutateAsync({
        id: player.id,
        data: {
          home_club: values.home_club || null,
          team: values.team || null,
          dominant_foot: values.dominant_foot || null,
          preferred_positions: values.preferred_positions,
          goals: values.goals || null,
          interests: values.interests
            ? values.interests
                .split(',')
                .map((item) => item.trim())
                .filter(Boolean)
            : [],
          notes_from_family: values.notes_from_family || null,
        },
      });
      await queryClient.invalidateQueries({ queryKey: playerQueryKey(player.id) });
      toast({ title: 'Soccer profile saved', variant: 'success' });
    } catch (error) {
      const applied = applyApiFieldErrors(error, { setError, fallbackField: 'goals' });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  return (
    <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
      <FormField label="Club" error={errors.home_club?.message}>
        <Input {...register('home_club')} />
      </FormField>
      <FormField label="Team" error={errors.team?.message}>
        <Input {...register('team')} />
      </FormField>
      <FormField label="Dominant foot">
        <Select
          aria-label="Dominant foot"
          value={watch('dominant_foot') ?? ''}
          onValueChange={(value) => setValue('dominant_foot', value)}
          options={[
            { value: '', label: 'Not sure' },
            { value: 'left', label: 'Left' },
            { value: 'right', label: 'Right' },
            { value: 'both', label: 'Both' },
          ]}
        />
      </FormField>
      <FormField label="Preferred positions">
        <div className="flex flex-wrap gap-3">
          {positions.map((position) => (
            <Checkbox
              key={position.id}
              label={position.label ?? position.code}
              checked={selected.includes(position.code)}
              onCheckedChange={(checked) =>
                setValue(
                  'preferred_positions',
                  checked
                    ? [...selected, position.code]
                    : selected.filter((code) => code !== position.code),
                )
              }
            />
          ))}
        </div>
      </FormField>
      <FormField label="Goals" error={errors.goals?.message}>
        <Textarea rows={2} {...register('goals')} />
      </FormField>
      <FormField label="Interests" help="Comma separated" error={errors.interests?.message}>
        <Input {...register('interests')} />
      </FormField>
      <FormField label="Notes from family" error={errors.notes_from_family?.message}>
        <Textarea rows={2} {...register('notes_from_family')} />
      </FormField>
      <div>
        <Button type="submit" disabled={mutation.isPending}>
          {mutation.isPending ? 'Saving…' : 'Save profile'}
        </Button>
      </div>
    </form>
  );
}
