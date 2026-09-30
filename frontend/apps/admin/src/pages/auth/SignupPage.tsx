import { zodResolver } from '@hookform/resolvers/zod';
import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { useTranslation } from 'react-i18next';
import { useNavigate } from 'react-router-dom';
import { z } from 'zod';
import {
  getSportsCoachBookingsWebPlatformSignupControllerSlugAvailableQueryKey,
  useSportsCoachBookingsWebPlatformSignupControllerCreate,
  useSportsCoachBookingsWebPlatformSignupControllerSlugAvailable,
} from '@scb/api-client';
import { Button, FormField, Input, Select } from '@scb/ui';
import { AuthLayout } from '../../layouts/AuthLayout';

const TIMEZONES = [
  'America/Toronto',
  'America/Vancouver',
  'America/New_York',
  'Europe/London',
  'Australia/Sydney',
];
const CURRENCIES = ['CAD', 'USD', 'GBP', 'AUD', 'NZD', 'EUR'];

const schema = z.object({
  name: z.string().min(1, 'auth.required'),
  slug: z
    .string()
    .min(2, 'auth.required')
    .regex(/^[a-z0-9-]+$/, 'auth.slugHint'),
  timezone: z.string().min(1, 'auth.required'),
  currency: z.string().min(1, 'auth.required'),
  email: z.string().email('auth.invalidEmail'),
  password: z.string().min(12, 'auth.passwordMin'),
});

type FormValues = z.infer<typeof schema>;

const STEP_FIELDS: (keyof FormValues)[][] = [
  ['name', 'slug'],
  ['timezone', 'currency'],
  ['email', 'password'],
];

export function SignupPage() {
  const { t } = useTranslation();
  const navigate = useNavigate();
  const signup = useSportsCoachBookingsWebPlatformSignupControllerCreate();
  const [step, setStep] = useState(0);
  const [debouncedSlug, setDebouncedSlug] = useState('');

  const {
    register,
    handleSubmit,
    watch,
    trigger,
    setValue,
    formState: { errors, isSubmitting },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: {
      name: '',
      slug: '',
      timezone: 'America/Toronto',
      currency: 'CAD',
      email: '',
      password: '',
    },
  });

  const slug = watch('slug');
  const timezone = watch('timezone');
  const currency = watch('currency');

  useEffect(() => {
    const handle = window.setTimeout(() => setDebouncedSlug(slug.trim().toLowerCase()), 300);
    return () => window.clearTimeout(handle);
  }, [slug]);

  const slugQuery = useSportsCoachBookingsWebPlatformSignupControllerSlugAvailable(
    { slug: debouncedSlug },
    {
      query: {
        queryKey: getSportsCoachBookingsWebPlatformSignupControllerSlugAvailableQueryKey({
          slug: debouncedSlug,
        }),
        enabled: debouncedSlug.length >= 2,
      },
    },
  );

  const slugAvailable = slugQuery.data?.data?.available;

  const next = async () => {
    const valid = await trigger(STEP_FIELDS[step]);
    if (!valid) return;
    if (step === 0 && slugAvailable === false) return;
    setStep((current) => Math.min(current + 1, STEP_FIELDS.length - 1));
  };

  const onSubmit = handleSubmit(async (values) => {
    await signup.mutateAsync({ data: values });
    navigate('/login', { replace: true });
  });

  return (
    <AuthLayout title={t('auth.signupTitle')} subtitle={t('auth.signupSubtitle')}>
      <div className="mb-4 flex gap-1" aria-label="Signup progress">
        {STEP_FIELDS.map((_, index) => (
          <span
            key={index}
            aria-hidden="true"
            className={`h-1.5 flex-1 rounded-full ${index <= step ? 'bg-primary' : 'bg-muted'}`}
          />
        ))}
      </div>

      <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
        {step === 0 ? (
          <>
            <FormField
              label={t('auth.businessName')}
              error={errors.name && t(errors.name.message ?? '')}
            >
              <Input {...register('name')} />
            </FormField>
            <FormField
              label={t('auth.slug')}
              help={t('auth.slugHint')}
              error={
                slugAvailable === false
                  ? t('auth.slugTaken')
                  : errors.slug && t(errors.slug.message ?? '')
              }
            >
              <Input {...register('slug')} />
            </FormField>
            {slugAvailable === true ? (
              <p role="status" className="text-xs text-green-700">
                {t('auth.slugAvailable')}
              </p>
            ) : null}
          </>
        ) : null}

        {step === 1 ? (
          <>
            <FormField
              label={t('auth.timezone')}
              error={errors.timezone && t(errors.timezone.message ?? '')}
            >
              <Select
                aria-label={t('auth.timezone')}
                value={timezone}
                onValueChange={(value) => setValue('timezone', value)}
                options={TIMEZONES.map((zone) => ({ value: zone, label: zone }))}
              />
            </FormField>
            <FormField
              label={t('auth.currency')}
              error={errors.currency && t(errors.currency.message ?? '')}
            >
              <Select
                aria-label={t('auth.currency')}
                value={currency}
                onValueChange={(value) => setValue('currency', value)}
                options={CURRENCIES.map((code) => ({ value: code, label: code }))}
              />
            </FormField>
          </>
        ) : null}

        {step === 2 ? (
          <>
            <FormField
              label={t('auth.email')}
              error={errors.email && t(errors.email.message ?? '')}
            >
              <Input type="email" autoComplete="email" {...register('email')} />
            </FormField>
            <FormField
              label={t('auth.password')}
              error={errors.password && t(errors.password.message ?? '')}
            >
              <Input type="password" autoComplete="new-password" {...register('password')} />
            </FormField>
          </>
        ) : null}

        <div className="flex justify-between gap-2">
          <Button
            type="button"
            variant="outline"
            onClick={() => setStep((current) => Math.max(current - 1, 0))}
            disabled={step === 0}
          >
            {t('common.back')}
          </Button>
          {step < STEP_FIELDS.length - 1 ? (
            <Button type="button" onClick={() => void next()}>
              {t('common.next')}
            </Button>
          ) : (
            <Button type="submit" disabled={isSubmitting}>
              {t('auth.createAccount')}
            </Button>
          )}
        </div>
      </form>
    </AuthLayout>
  );
}
