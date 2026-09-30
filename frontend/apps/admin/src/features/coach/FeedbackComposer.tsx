import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { applyApiFieldErrors } from '@scb/api-client';
import {
  Button,
  ConfirmDialog,
  Drawer,
  FormField,
  Input,
  Switch,
  Textarea,
  cn,
  useToast,
} from '@scb/ui';
import {
  feedbackQueryKey,
  useCreateFeedback,
  useFeedback,
  useShareFeedback,
  useSkillTags,
  useUpdateFeedback,
  type CoachSkillTag,
} from '../../api/endpoints';
import { body, errorMessage } from '../shared/api-utils';
import { MarkdownPreview } from '../shared/MarkdownPreview';
import type { CoachFeedbackRecord, CoachFeedbackVisibility } from './types';

const schema = z.object({
  body: z.string().min(1, 'Add a note before saving'),
  focus_next: z.string(),
  notify: z.boolean(),
});

type FormValues = z.infer<typeof schema>;

const DEFAULTS: FormValues = { body: '', focus_next: '', notify: false };

function skillTagItems(query: unknown): CoachSkillTag[] {
  return (
    (query as { data?: { data?: { data?: CoachSkillTag[] } } } | undefined)?.data?.data?.data ?? []
  );
}

export function FeedbackComposer({
  open,
  onOpenChange,
  sessionId,
  playerId,
  playerName,
  feedbackId,
  onSaved,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  sessionId: string;
  playerId: string;
  playerName: string;
  feedbackId?: string | null;
  onSaved?: () => void;
}) {
  const { toast } = useToast();
  const skillTags = skillTagItems(useSkillTags());

  const existingQuery = useFeedback(feedbackId ?? '', {
    query: {
      enabled: open && Boolean(feedbackId),
      queryKey: feedbackQueryKey(feedbackId ?? ''),
    },
  });
  const existing = body<CoachFeedbackRecord>(existingQuery);
  const existingVisibility: CoachFeedbackVisibility['visibility'] =
    existing?.visibility === 'shared' ? 'shared' : 'internal';

  const createFeedback = useCreateFeedback();
  const updateFeedback = useUpdateFeedback();
  const shareFeedback = useShareFeedback();

  const [ratings, setRatings] = useState<Record<string, number>>({});
  const [confirmShareOpen, setConfirmShareOpen] = useState(false);
  const [pendingShare, setPendingShare] = useState(false);

  const {
    register,
    handleSubmit,
    reset,
    setError,
    setValue,
    watch,
    formState: { errors },
  } = useForm<FormValues>({ resolver: zodResolver(schema), defaultValues: DEFAULTS });

  useEffect(() => {
    if (!open) return;
    reset({
      body: existing?.body ?? '',
      focus_next: existing?.focus_next ?? '',
      notify: false,
    });
    setRatings(existing?.skill_ratings ?? {});
  }, [open, existing, reset]);

  const bodyValue = watch('body');
  const notify = watch('notify');

  const submit = handleSubmit(async (values) => {
    const skill_ratings = Object.keys(ratings).length > 0 ? ratings : undefined;
    try {
      if (!feedbackId) {
        await createFeedback.mutateAsync({
          data: {
            session_id: sessionId,
            player_id: playerId,
            body: values.body,
            skill_ratings: skill_ratings ?? null,
            focus_next: values.focus_next || null,
            visibility: pendingShare ? 'shared' : 'internal',
          },
        });
        toast({
          title: pendingShare ? 'Feedback shared with family' : 'Draft saved',
          variant: 'success',
        });
      } else if (pendingShare && existingVisibility === 'internal') {
        await updateFeedback.mutateAsync({
          id: feedbackId,
          data: {
            body: values.body,
            skill_ratings: skill_ratings ?? null,
            focus_next: values.focus_next || null,
          },
        });
        await shareFeedback.mutateAsync({ id: feedbackId });
        toast({ title: 'Feedback shared with family', variant: 'success' });
      } else {
        await updateFeedback.mutateAsync({
          id: feedbackId,
          data: {
            body: values.body,
            skill_ratings: skill_ratings ?? null,
            focus_next: values.focus_next || null,
            visibility: existingVisibility,
            notify: values.notify,
          },
        });
        toast({ title: 'Feedback updated', variant: 'success' });
      }
      onSaved?.();
      onOpenChange(false);
    } catch (error) {
      const applied = applyApiFieldErrors(error, { setError, fallbackField: 'body' });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    } finally {
      setPendingShare(false);
    }
  });

  const requestShare = () => {
    setPendingShare(true);
    setConfirmShareOpen(true);
  };

  const isShared = existingVisibility === 'shared' && Boolean(feedbackId);
  const saving = createFeedback.isPending || updateFeedback.isPending || shareFeedback.isPending;

  return (
    <>
      <Drawer
        open={open}
        onOpenChange={onOpenChange}
        title={`Feedback for ${playerName}`}
        description="Write a session note, rate the focus skills, and decide whether to share it."
        footer={
          <div className="flex flex-wrap justify-end gap-2">
            {!isShared ? (
              <>
                <Button
                  variant="outline"
                  onClick={() => {
                    setPendingShare(false);
                    void submit();
                  }}
                  disabled={saving}
                >
                  Save draft
                </Button>
                <Button onClick={requestShare} disabled={saving}>
                  Share with family
                </Button>
              </>
            ) : (
              <Button onClick={() => void submit()} disabled={saving}>
                Save changes
              </Button>
            )}
          </div>
        }
      >
        <form
          className="flex flex-col gap-4"
          onSubmit={(event) => event.preventDefault()}
          noValidate
        >
          <FormField label="Session note" required error={errors.body?.message}>
            <Textarea
              aria-label="Session note"
              rows={5}
              placeholder="What went well, what to work on…"
              {...register('body')}
            />
          </FormField>

          {bodyValue ? (
            <div className="rounded-md border border-border bg-background p-3">
              <p className="mb-1 text-xs font-medium text-muted-foreground">Preview</p>
              <MarkdownPreview markdown={bodyValue} />
            </div>
          ) : null}

          <FormField label="Focus next session">
            <Input aria-label="Focus next session" {...register('focus_next')} />
          </FormField>

          <fieldset className="flex flex-col gap-3">
            <legend className="text-sm font-medium">Skill ratings</legend>
            {skillTags.length === 0 ? (
              <p className="text-sm text-muted-foreground">No skill tags configured.</p>
            ) : (
              skillTags.map((tag) => (
                <div key={tag.id} className="flex flex-col gap-1">
                  <span className="text-sm">{tag.name}</span>
                  <div className="flex gap-1" role="group" aria-label={`${tag.name} rating`}>
                    {[1, 2, 3, 4, 5].map((value) => (
                      <button
                        key={value}
                        type="button"
                        aria-pressed={ratings[tag.slug] === value}
                        aria-label={`${tag.name} ${value}`}
                        onClick={() => setRatings((prev) => ({ ...prev, [tag.slug]: value }))}
                        className={cn(
                          'h-10 w-10 rounded-md border text-sm font-medium focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring',
                          ratings[tag.slug] === value
                            ? 'border-primary bg-primary text-primary-foreground'
                            : 'border-border bg-surface hover:bg-muted',
                        )}
                      >
                        {value}
                      </button>
                    ))}
                  </div>
                </div>
              ))
            )}
          </fieldset>

          {isShared ? (
            <Switch
              label="Notify the family that this was updated"
              checked={notify}
              onCheckedChange={(checked) => setValue('notify', checked)}
            />
          ) : null}
        </form>
      </Drawer>

      <ConfirmDialog
        open={confirmShareOpen}
        onOpenChange={setConfirmShareOpen}
        title="Share feedback with the family?"
        description="Sharing sends this note to the player's household and cannot be unshared. You can still edit it for 48 hours."
        confirmLabel="Share now"
        onConfirm={() => {
          setConfirmShareOpen(false);
          void submit();
        }}
        loading={saving}
      />
    </>
  );
}
