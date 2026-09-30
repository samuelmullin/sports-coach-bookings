import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import { Controller, useFieldArray, useForm } from 'react-hook-form';
import { ArrowDown, ArrowUp, Plus, Trash2 } from 'lucide-react';
import { applyApiFieldErrors } from '@scb/api-client';
import {
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Checkbox,
  FormField,
  Input,
  Select,
  Switch,
  Textarea,
  useToast,
} from '@scb/ui';
import {
  useAssignPolicy,
  useOfferings,
  usePolicy,
  useUnassignPolicy,
  useUpdatePolicy,
  type PolicyRequest,
  type PolicyRules,
} from '../../api/endpoints';
import { body, errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';
import { defaultPolicyRules } from './defaults';
import { PolicySimulator } from './PolicySimulator';

interface EditorForm {
  name: string;
  customer_facing_summary: string;
  rules: PolicyRules;
}

export function PolicyEditorPage() {
  const { policyId = '' } = useParams();
  const query = usePolicy(policyId);
  const update = useUpdatePolicy();
  const assign = useAssignPolicy();
  const unassign = useUnassignPolicy();
  const offeringsQuery = useOfferings();
  const { toast } = useToast();
  const navigate = useNavigate();

  const policy = body<{
    id: string;
    name: string;
    version: number;
    customer_facing_summary: string | null;
    assigned_offering_ids?: string[];
    rules: PolicyRules;
  }>(query);
  const offerings = listItems<{ id: string; name: string }>(offeringsQuery);

  const [assigned, setAssigned] = useState<string[]>([]);
  const [originalAssigned, setOriginalAssigned] = useState<string[]>([]);

  const { register, control, handleSubmit, reset, setError, watch, setValue } = useForm<EditorForm>(
    {
      defaultValues: {
        name: '',
        customer_facing_summary: '',
        rules: defaultPolicyRules,
      },
    },
  );
  const tiers = useFieldArray({ control, name: 'rules.cancellation_tiers' });

  useEffect(() => {
    if (!policy) return;
    reset({
      name: policy.name,
      customer_facing_summary: policy.customer_facing_summary ?? '',
      rules: policy.rules ?? defaultPolicyRules,
    });
    setAssigned(policy.assigned_offering_ids ?? []);
    setOriginalAssigned(policy.assigned_offering_ids ?? []);
  }, [policy, reset]);

  const onSubmit = handleSubmit(async (values) => {
    const payload: PolicyRequest = {
      name: values.name,
      customer_facing_summary: values.customer_facing_summary || null,
      rules: values.rules,
    };
    try {
      await update.mutateAsync({ id: policyId, data: payload });
      toast({ title: 'Policy saved', variant: 'success' });
    } catch (error) {
      const applied = applyApiFieldErrors(error, { setError, fallbackField: 'name' });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  const saveAssignments = async () => {
    const added = assigned.filter((id) => !originalAssigned.includes(id));
    const removed = originalAssigned.filter((id) => !assigned.includes(id));
    try {
      if (added.length > 0) {
        await assign.mutateAsync({ id: policyId, data: { offering_ids: added } });
      }
      for (const offeringId of removed) {
        await unassign.mutateAsync({ offeringId });
      }
      setOriginalAssigned(assigned);
      toast({ title: 'Offering assignments saved', variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  const moveTier = (index: number, delta: number) => {
    const target = index + delta;
    if (target < 0 || target >= tiers.fields.length) return;
    tiers.move(index, target);
  };

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title={policy?.name ?? 'Policy'}
        description={policy ? `Version ${policy.version}` : undefined}
        actions={
          <Button variant="outline" onClick={() => navigate('/policies')}>
            Back to policies
          </Button>
        }
      />

      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        <div className="grid gap-4 lg:grid-cols-2">
          <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
            <Card>
              <CardHeader>
                <CardTitle>Details</CardTitle>
              </CardHeader>
              <CardContent className="flex flex-col gap-4">
                <FormField label="Name" required>
                  <Input {...register('name')} />
                </FormField>
                <FormField label="Customer-facing summary">
                  <Textarea {...register('customer_facing_summary')} />
                </FormField>
              </CardContent>
            </Card>

            <Card>
              <CardHeader className="flex-row items-center justify-between">
                <CardTitle>Cancellation tiers</CardTitle>
                <Button
                  type="button"
                  variant="outline"
                  size="sm"
                  onClick={() =>
                    tiers.append({
                      min_hours_before: 24,
                      money_refund_pct: 0,
                      credit_outcome: 'return',
                    })
                  }
                >
                  <Plus className="h-3.5 w-3.5" aria-hidden="true" />
                  Add tier
                </Button>
              </CardHeader>
              <CardContent className="flex flex-col gap-3">
                {tiers.fields.length === 0 ? (
                  <p className="text-sm text-muted-foreground">
                    No tiers — cancellations fall through.
                  </p>
                ) : (
                  tiers.fields.map((field, index) => (
                    <div
                      key={field.id}
                      className="grid grid-cols-[1fr_1fr_auto_auto] items-end gap-2 rounded-md border border-border p-2"
                    >
                      <FormField label="Hours before">
                        <Input
                          type="number"
                          aria-label={`Tier ${index + 1} hours before`}
                          {...register(`rules.cancellation_tiers.${index}.min_hours_before`, {
                            valueAsNumber: true,
                          })}
                        />
                      </FormField>
                      <FormField label="Refund %">
                        <Input
                          type="number"
                          aria-label={`Tier ${index + 1} refund percent`}
                          {...register(`rules.cancellation_tiers.${index}.money_refund_pct`, {
                            valueAsNumber: true,
                          })}
                        />
                      </FormField>
                      <Controller
                        control={control}
                        name={`rules.cancellation_tiers.${index}.credit_outcome`}
                        render={({ field: select }) => (
                          <FormField label="Sessions">
                            <Select
                              aria-label={`Tier ${index + 1} session outcome`}
                              value={select.value}
                              onValueChange={select.onChange}
                              options={[
                                { value: 'return', label: 'Return' },
                                { value: 'forfeit', label: 'Forfeit' },
                              ]}
                            />
                          </FormField>
                        )}
                      />
                      <div className="flex gap-1 pb-1">
                        <Button
                          type="button"
                          variant="ghost"
                          size="sm"
                          aria-label={`Move tier ${index + 1} up`}
                          onClick={() => moveTier(index, -1)}
                        >
                          <ArrowUp className="h-3.5 w-3.5" />
                        </Button>
                        <Button
                          type="button"
                          variant="ghost"
                          size="sm"
                          aria-label={`Move tier ${index + 1} down`}
                          onClick={() => moveTier(index, 1)}
                        >
                          <ArrowDown className="h-3.5 w-3.5" />
                        </Button>
                        <Button
                          type="button"
                          variant="ghost"
                          size="sm"
                          aria-label={`Remove tier ${index + 1}`}
                          onClick={() => tiers.remove(index)}
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </Button>
                      </div>
                    </div>
                  ))
                )}
                <Switch
                  label="Late cancellation counts as a no-show"
                  checked={watch('rules.late_cancel_counts_as_no_show')}
                  onCheckedChange={(checked) =>
                    setValue('rules.late_cancel_counts_as_no_show', checked)
                  }
                />
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>No-show & provider cancellation</CardTitle>
              </CardHeader>
              <CardContent className="grid gap-4 sm:grid-cols-2">
                <FormField label="No-show refund %">
                  <Input
                    type="number"
                    {...register('rules.no_show.money_refund_pct', { valueAsNumber: true })}
                  />
                </FormField>
                <Controller
                  control={control}
                  name="rules.no_show.credit_outcome"
                  render={({ field }) => (
                    <FormField label="No-show sessions">
                      <Select
                        aria-label="No-show sessions"
                        value={field.value}
                        onValueChange={field.onChange}
                        options={[
                          { value: 'return', label: 'Return' },
                          { value: 'forfeit', label: 'Forfeit' },
                        ]}
                      />
                    </FormField>
                  )}
                />
                <FormField label="Provider cancel refund %">
                  <Input
                    type="number"
                    {...register('rules.provider_cancelled.money_refund_pct', {
                      valueAsNumber: true,
                    })}
                  />
                </FormField>
                <Controller
                  control={control}
                  name="rules.provider_cancelled.credit_outcome"
                  render={({ field }) => (
                    <FormField label="Provider cancel sessions">
                      <Select
                        aria-label="Provider cancel sessions"
                        value={field.value}
                        onValueChange={field.onChange}
                        options={[
                          { value: 'return', label: 'Return' },
                          { value: 'forfeit', label: 'Forfeit' },
                        ]}
                      />
                    </FormField>
                  )}
                />
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Rebooking</CardTitle>
              </CardHeader>
              <CardContent className="flex flex-col gap-4">
                <Switch
                  label="Allow rebooking"
                  checked={watch('rules.rebook.allowed')}
                  onCheckedChange={(checked) => setValue('rules.rebook.allowed', checked)}
                />
                <div className="grid gap-4 sm:grid-cols-2">
                  <FormField label="Minimum hours before">
                    <Input
                      type="number"
                      {...register('rules.rebook.min_hours_before', { valueAsNumber: true })}
                    />
                  </FormField>
                  <FormField label="Max rebooks per booking">
                    <Input
                      type="number"
                      {...register('rules.rebook.max_rebooks_per_booking', {
                        setValueAs: (value) => (value === '' ? null : Number(value)),
                      })}
                    />
                  </FormField>
                </div>
                <Switch
                  label="Same offering only"
                  checked={watch('rules.rebook.same_offering_only')}
                  onCheckedChange={(checked) =>
                    setValue('rules.rebook.same_offering_only', checked)
                  }
                />
              </CardContent>
            </Card>

            <div className="flex justify-end">
              <Button type="submit" disabled={update.isPending}>
                Save policy
              </Button>
            </div>
          </form>

          <div className="flex flex-col gap-4">
            <Card>
              <CardHeader>
                <CardTitle>Offering assignments</CardTitle>
              </CardHeader>
              <CardContent className="flex flex-col gap-3">
                {offerings.map((offering) => (
                  <Checkbox
                    key={offering.id}
                    label={offering.name}
                    checked={assigned.includes(offering.id)}
                    onCheckedChange={(checked) =>
                      setAssigned((current) =>
                        checked
                          ? [...current, offering.id]
                          : current.filter((id) => id !== offering.id),
                      )
                    }
                  />
                ))}
                <div className="flex justify-end">
                  <Button
                    variant="outline"
                    size="sm"
                    onClick={() => void saveAssignments()}
                    disabled={assign.isPending || unassign.isPending}
                  >
                    Save assignments
                  </Button>
                </div>
              </CardContent>
            </Card>

            <PolicySimulator policyId={policyId} />
          </div>
        </div>
      </QueryState>
    </div>
  );
}
