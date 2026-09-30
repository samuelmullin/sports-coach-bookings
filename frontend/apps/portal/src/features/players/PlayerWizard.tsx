import { useState } from 'react';
import { useFieldArray, useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { Trash2 } from 'lucide-react';
import { applyApiFieldErrors } from '@scb/api-client';
import { Button, Checkbox, Drawer, FormField, Input, Select, Textarea, useToast } from '@scb/ui';
import {
  playersQueryKey,
  useCreateAuthorizedPickup,
  useCreateEmergencyContact,
  useCreatePlayer,
  usePositionOptions,
  useUpdatePlayerMedical,
  useUpdatePlayerProfile,
  type PositionOptionResponse,
  type PlayerResponse,
} from '../../api/endpoints';
import { errorMessage, listItems, responseData } from '../shared/api-utils';
import { useReservationTouch } from '../reservations/useReservationTouch';

const contactSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  phone: z.string().min(1, 'Phone is required'),
  relationship: z.string().optional(),
});

const pickupSchema = z.object({
  name: z.string().min(1, 'Name is required'),
  phone: z.string().optional(),
  relationship: z.string().optional(),
});

const schema = z.object({
  first_name: z.string().min(1, 'First name is required'),
  last_name: z.string().min(1, 'Last name is required'),
  date_of_birth: z.string().min(1, 'Date of birth is required'),
  preferred_name: z.string().optional(),
  team: z.string().optional(),
  home_club: z.string().optional(),
  dominant_foot: z.string().optional(),
  preferred_positions: z.array(z.string()),
  goals: z.string().optional(),
  interests: z.string().optional(),
  notes_from_family: z.string().optional(),
  contacts: z.array(contactSchema).min(1, 'Add at least one emergency contact'),
  pickups: z.array(pickupSchema),
  allergies: z.string().optional(),
  conditions: z.string().optional(),
  medications: z.string().optional(),
  medical_notes: z.string().optional(),
});

type FormValues = z.infer<typeof schema>;

const STEPS = ['Basics', 'Soccer profile', 'Emergency contacts', 'Pickups', 'Medical'] as const;

const DEFAULTS: FormValues = {
  first_name: '',
  last_name: '',
  date_of_birth: '',
  preferred_name: '',
  team: '',
  home_club: '',
  dominant_foot: '',
  preferred_positions: [],
  goals: '',
  interests: '',
  notes_from_family: '',
  contacts: [{ name: '', phone: '', relationship: '' }],
  pickups: [],
  allergies: '',
  conditions: '',
  medications: '',
  medical_notes: '',
};

export function PlayerWizard({
  open,
  onOpenChange,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const [step, setStep] = useState(0);
  const { toast } = useToast();
  const queryClient = useQueryClient();
  const touchReservation = useReservationTouch();

  const createPlayer = useCreatePlayer();
  const updateProfile = useUpdatePlayerProfile();
  const createContact = useCreateEmergencyContact();
  const createPickup = useCreateAuthorizedPickup();
  const updateMedical = useUpdatePlayerMedical();
  const positions = listItems<PositionOptionResponse>(usePositionOptions());

  const {
    register,
    handleSubmit,
    trigger,
    reset,
    setError,
    watch,
    setValue,
    control,
    formState: { errors },
  } = useForm<FormValues>({ resolver: zodResolver(schema), defaultValues: DEFAULTS });

  const contacts = useFieldArray({ control, name: 'contacts' });
  const pickups = useFieldArray({ control, name: 'pickups' });
  const selectedPositions = watch('preferred_positions');

  const submitting =
    createPlayer.isPending ||
    updateProfile.isPending ||
    createContact.isPending ||
    createPickup.isPending ||
    updateMedical.isPending;

  const next = async () => {
    const fieldsToValidate: (keyof FormValues)[][] = [
      ['first_name', 'last_name', 'date_of_birth'],
      [],
      ['contacts'],
      [],
      [],
    ];
    const valid = await trigger(fieldsToValidate[step] as never);
    if (valid) setStep((current) => Math.min(current + 1, STEPS.length - 1));
  };

  const onSubmit = handleSubmit(async (values) => {
    try {
      const created = responseData<PlayerResponse>(
        await createPlayer.mutateAsync({
          data: {
            first_name: values.first_name,
            last_name: values.last_name,
            date_of_birth: values.date_of_birth,
            preferred_name: values.preferred_name || null,
            is_self: false,
          },
        }),
      );
      const playerId = created?.id;
      if (!playerId) throw new Error('Player could not be created');

      const hasProfile = Boolean(
        values.team ||
        values.home_club ||
        values.dominant_foot ||
        values.goals ||
        values.notes_from_family ||
        values.interests ||
        values.preferred_positions.length,
      );
      if (hasProfile) {
        await updateProfile.mutateAsync({
          id: playerId,
          data: {
            team: values.team || null,
            home_club: values.home_club || null,
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
      }

      await Promise.all(
        values.contacts.map((contact, index) =>
          createContact.mutateAsync({
            playerId,
            data: {
              name: contact.name,
              phone: contact.phone,
              relationship: contact.relationship || null,
              priority: index + 1,
            },
          }),
        ),
      );

      await Promise.all(
        values.pickups.map((pickup) =>
          createPickup.mutateAsync({
            playerId,
            data: {
              name: pickup.name,
              phone: pickup.phone || null,
              relationship: pickup.relationship || null,
              notes: null,
            },
          }),
        ),
      );

      const hasMedical = Boolean(
        values.allergies || values.conditions || values.medications || values.medical_notes,
      );
      if (hasMedical) {
        await updateMedical.mutateAsync({
          id: playerId,
          data: {
            allergies: values.allergies || null,
            conditions: values.conditions || null,
            medications: values.medications || null,
            notes: values.medical_notes || null,
          },
        });
      }

      await touchReservation();
      await queryClient.invalidateQueries({ queryKey: playersQueryKey() });
      toast({ title: 'Player added', variant: 'success' });
      reset(DEFAULTS);
      setStep(0);
      onOpenChange(false);
    } catch (error) {
      const applied = applyApiFieldErrors(error, {
        setError,
        mappedFields: { first_name: 'first_name', last_name: 'last_name' },
        fallbackField: 'first_name',
      });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  return (
    <Drawer
      open={open}
      onOpenChange={onOpenChange}
      title="Add a player"
      description={`Step ${step + 1} of ${STEPS.length}: ${STEPS[step]}`}
      footer={
        <>
          {step > 0 ? (
            <Button variant="outline" onClick={() => setStep((current) => current - 1)}>
              Back
            </Button>
          ) : null}
          {step < STEPS.length - 1 ? (
            <Button onClick={() => void next()}>Continue</Button>
          ) : (
            <Button onClick={() => void onSubmit()} disabled={submitting}>
              {submitting ? 'Saving…' : 'Finish'}
            </Button>
          )}
        </>
      }
    >
      <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
        {step === 0 ? (
          <>
            <FormField label="First name" required error={errors.first_name?.message}>
              <Input {...register('first_name')} />
            </FormField>
            <FormField label="Last name" required error={errors.last_name?.message}>
              <Input {...register('last_name')} />
            </FormField>
            <FormField
              label="Date of birth"
              required
              error={errors.date_of_birth?.message}
              help="Used to check age eligibility for sessions."
            >
              <Input type="date" {...register('date_of_birth')} />
            </FormField>
            <FormField label="Preferred name" error={errors.preferred_name?.message}>
              <Input {...register('preferred_name')} />
            </FormField>
          </>
        ) : null}

        {step === 1 ? (
          <>
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
                    checked={selectedPositions.includes(position.code)}
                    onCheckedChange={(checked) =>
                      setValue(
                        'preferred_positions',
                        checked
                          ? [...selectedPositions, position.code]
                          : selectedPositions.filter((code) => code !== position.code),
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
          </>
        ) : null}

        {step === 2 ? (
          <>
            {errors.contacts?.message ? (
              <p role="alert" className="text-sm font-medium text-danger">
                {errors.contacts.message}
              </p>
            ) : null}
            {contacts.fields.map((field, index) => (
              <div
                key={field.id}
                className="flex flex-col gap-3 rounded-md border border-border p-3"
              >
                <FormField label="Name" required error={errors.contacts?.[index]?.name?.message}>
                  <Input {...register(`contacts.${index}.name`)} />
                </FormField>
                <FormField label="Phone" required error={errors.contacts?.[index]?.phone?.message}>
                  <Input type="tel" {...register(`contacts.${index}.phone`)} />
                </FormField>
                <FormField label="Relationship">
                  <Input {...register(`contacts.${index}.relationship`)} />
                </FormField>
                {contacts.fields.length > 1 ? (
                  <Button
                    type="button"
                    variant="ghost"
                    size="sm"
                    className="self-start text-danger"
                    onClick={() => contacts.remove(index)}
                  >
                    <Trash2 className="h-4 w-4" aria-hidden="true" /> Remove
                  </Button>
                ) : null}
              </div>
            ))}
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => contacts.append({ name: '', phone: '', relationship: '' })}
            >
              Add another contact
            </Button>
          </>
        ) : null}

        {step === 3 ? (
          <>
            {pickups.fields.map((field, index) => (
              <div
                key={field.id}
                className="flex flex-col gap-3 rounded-md border border-border p-3"
              >
                <FormField label="Name" required error={errors.pickups?.[index]?.name?.message}>
                  <Input {...register(`pickups.${index}.name`)} />
                </FormField>
                <FormField label="Phone">
                  <Input type="tel" {...register(`pickups.${index}.phone`)} />
                </FormField>
                <FormField label="Relationship">
                  <Input {...register(`pickups.${index}.relationship`)} />
                </FormField>
                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  className="self-start text-danger"
                  onClick={() => pickups.remove(index)}
                >
                  <Trash2 className="h-4 w-4" aria-hidden="true" /> Remove
                </Button>
              </div>
            ))}
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => pickups.append({ name: '', phone: '', relationship: '' })}
            >
              Add authorized pickup
            </Button>
          </>
        ) : null}

        {step === 4 ? (
          <>
            <p className="rounded-md bg-muted p-3 text-xs text-muted-foreground">
              Medical information is private. It is only visible to club staff who need it for
              safety, and is never shown in lists.
            </p>
            <FormField label="Allergies">
              <Textarea rows={2} {...register('allergies')} />
            </FormField>
            <FormField label="Conditions">
              <Textarea rows={2} {...register('conditions')} />
            </FormField>
            <FormField label="Medications">
              <Textarea rows={2} {...register('medications')} />
            </FormField>
            <FormField label="Notes">
              <Textarea rows={2} {...register('medical_notes')} />
            </FormField>
          </>
        ) : null}
      </form>
    </Drawer>
  );
}
