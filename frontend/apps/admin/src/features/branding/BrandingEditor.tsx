import { Controller, useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useEffect } from 'react';
import { applyApiFieldErrors } from '@scb/api-client';
import {
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  FileUpload,
  FormField,
  Input,
  Skeleton,
} from '@scb/ui';
import {
  useBranding,
  useCreateBrandingUpload,
  useUpdateBranding,
  type Branding,
  type BrandingUpload,
} from '../../api/endpoints';
import { body, errorMessage, responseData } from '../shared/api-utils';
import { FONT_OPTIONS, Select, useToast } from '@scb/ui';
import { contrastWarning } from './contrast';

const hex = z.string().regex(/^#[0-9a-fA-F]{6}$/, 'Use a hex colour like #15803d');

const schema = z.object({
  primary_color: hex,
  secondary_color: hex,
  accent_color: hex,
  background_color: hex,
  text_color: hex,
  font_family: z.string().min(1, 'Font family is required'),
  email_footer_text: z.string(),
  instagram: z.string(),
  facebook: z.string(),
  logo_key: z.string().nullable(),
  favicon_key: z.string().nullable(),
});

type FormValues = z.infer<typeof schema>;

const DEFAULTS: FormValues = {
  primary_color: '#15803d',
  secondary_color: '#166534',
  accent_color: '#f59e0b',
  background_color: '#f8fafc',
  text_color: '#0f172a',
  font_family: 'inter',
  email_footer_text: '',
  instagram: '',
  facebook: '',
  logo_key: null,
  favicon_key: null,
};

function toForm(branding: Branding): FormValues {
  const social = branding.social_links as Record<string, unknown> | undefined;
  return {
    primary_color: branding.theme?.primary_color ?? DEFAULTS.primary_color,
    secondary_color: branding.theme?.secondary_color ?? DEFAULTS.secondary_color,
    accent_color: branding.theme?.accent_color ?? DEFAULTS.accent_color,
    background_color: branding.theme?.background_color ?? DEFAULTS.background_color,
    text_color: branding.theme?.text_color ?? DEFAULTS.text_color,
    font_family: branding.theme?.font_family ?? DEFAULTS.font_family,
    email_footer_text: branding.email_footer_text ?? '',
    instagram: typeof social?.instagram === 'string' ? social.instagram : '',
    facebook: typeof social?.facebook === 'string' ? social.facebook : '',
    logo_key: null,
    favicon_key: null,
  };
}

export function BrandingEditor() {
  const brandingQuery = useBranding();
  const update = useUpdateBranding();
  const createUpload = useCreateBrandingUpload();
  const { toast } = useToast();
  const branding = body<Branding>(brandingQuery);

  const { control, register, handleSubmit, reset, watch, setValue, setError } = useForm<FormValues>(
    { resolver: zodResolver(schema), defaultValues: DEFAULTS },
  );

  useEffect(() => {
    if (branding) reset(toForm(branding));
  }, [branding, reset]);

  const values = watch();

  const warnings = [
    contrastWarning(values.text_color, values.background_color, 'Body text on page'),
    contrastWarning('#ffffff', values.primary_color, 'Button label on primary'),
    contrastWarning('#ffffff', values.secondary_color, 'Button label on secondary'),
  ].filter((warning): warning is string => warning !== null);

  const uploadFor = (field: 'logo_key' | 'favicon_key') => async (file: File) => {
    const result = await createUpload.mutateAsync({
      data: {
        filename: file.name,
        content_type: (file.type || 'image/png') as never,
        byte_size: file.size,
      },
    });
    const payload = responseData<BrandingUpload>(result);
    if (!payload) throw new Error('Upload could not be prepared');
    setValue(field, payload.key ?? null);
    return {
      uploadUrl: payload.upload_url,
      fileUrl: payload.key ?? '',
      key: payload.key,
      headers: (payload.headers as Record<string, string>) ?? {},
    };
  };

  const onSubmit = handleSubmit(async (form) => {
    try {
      await update.mutateAsync({
        data: {
          primary_color: form.primary_color,
          secondary_color: form.secondary_color,
          accent_color: form.accent_color,
          background_color: form.background_color,
          text_color: form.text_color,
          font_family: form.font_family,
          email_footer_text: form.email_footer_text,
          logo_key: form.logo_key ?? undefined,
          favicon_key: form.favicon_key ?? undefined,
          social_links: {
            ...(form.instagram ? { instagram: form.instagram } : {}),
            ...(form.facebook ? { facebook: form.facebook } : {}),
          },
        },
      });
      toast({ title: 'Branding saved', variant: 'success' });
    } catch (error) {
      const applied = applyApiFieldErrors(error, { setError, fallbackField: 'primary_color' });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  if (brandingQuery.isLoading) return <Skeleton className="h-64 w-full" />;

  const colorFields: { name: keyof FormValues; label: string }[] = [
    { name: 'primary_color', label: 'Primary' },
    { name: 'secondary_color', label: 'Secondary' },
    { name: 'accent_color', label: 'Accent' },
    { name: 'background_color', label: 'Background' },
    { name: 'text_color', label: 'Text' },
  ];

  return (
    <div className="grid gap-4 lg:grid-cols-[1fr_360px]">
      <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
        <Card>
          <CardHeader>
            <CardTitle>Brand assets</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            <FileUpload
              label="Upload logo"
              accept="image/*"
              getPresignedUrl={uploadFor('logo_key')}
              onUploaded={(_file, result) => {
                if (result.key) toast({ title: 'Logo uploaded', variant: 'success' });
              }}
            />
            <FileUpload
              label="Upload favicon"
              accept="image/*"
              getPresignedUrl={uploadFor('favicon_key')}
            />
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Colours</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            <div className="grid gap-3 sm:grid-cols-2">
              {colorFields.map(({ name, label }) => (
                <Controller
                  key={name}
                  control={control}
                  name={name}
                  render={({ field }) => (
                    <FormField label={label} error={undefined}>
                      <div className="flex items-center gap-2">
                        <input
                          type="color"
                          aria-label={`${label} colour`}
                          value={typeof field.value === 'string' ? field.value : '#000000'}
                          onChange={(event) => field.onChange(event.target.value)}
                          className="h-10 w-12 cursor-pointer rounded border border-border bg-surface"
                        />
                        <Input
                          aria-label={`${label} hex`}
                          value={typeof field.value === 'string' ? field.value : ''}
                          onChange={(event) => field.onChange(event.target.value)}
                        />
                      </div>
                    </FormField>
                  )}
                />
              ))}
            </div>
            <FormField label="Font family">
              <Controller
                control={control}
                name="font_family"
                render={({ field }) => (
                  <Select
                    aria-label="Font family"
                    value={field.value}
                    onValueChange={field.onChange}
                    options={FONT_OPTIONS}
                  />
                )}
              />
            </FormField>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Email & social</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            <FormField label="Email footer text">
              <Input {...register('email_footer_text')} />
            </FormField>
            <div className="grid gap-4 sm:grid-cols-2">
              <FormField label="Instagram URL">
                <Input {...register('instagram')} />
              </FormField>
              <FormField label="Facebook URL">
                <Input {...register('facebook')} />
              </FormField>
            </div>
          </CardContent>
        </Card>

        <div className="flex justify-end">
          <Button type="submit" disabled={update.isPending}>
            {update.isPending ? 'Saving…' : 'Save branding'}
          </Button>
        </div>
      </form>

      <div className="flex flex-col gap-4">
        <Card>
          <CardHeader>
            <CardTitle>Live preview</CardTitle>
          </CardHeader>
          <CardContent className="flex flex-col gap-4">
            <div
              className="rounded-lg p-4 shadow-sm"
              style={{ background: values.background_color, color: values.text_color }}
              data-testid="portal-card-preview"
            >
              <div
                className="mb-3 h-16 rounded"
                style={{
                  background: `linear-gradient(135deg, ${values.primary_color}, ${values.secondary_color})`,
                }}
              />
              <p className="text-sm font-semibold">Spring Skills Clinic</p>
              <p className="text-xs opacity-80">8 sessions · Ages 7–10</p>
              <button
                type="button"
                className="mt-3 rounded-md px-3 py-2 text-sm font-medium text-white"
                style={{ background: values.primary_color }}
              >
                Book now
              </button>
            </div>

            <div
              className="overflow-hidden rounded-lg border border-border"
              data-testid="email-preview"
            >
              <div
                className="p-3 text-sm font-semibold text-white"
                style={{ background: values.primary_color }}
              >
                {branding?.tenant?.name ?? 'Your business'}
              </div>
              <div className="p-3 text-xs text-foreground">
                <p>Hi Pat, this is a reminder about your upcoming session.</p>
                <p className="mt-2 text-muted-foreground">{values.email_footer_text}</p>
              </div>
            </div>
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>Accessibility</CardTitle>
          </CardHeader>
          <CardContent>
            {warnings.length === 0 ? (
              <p className="text-sm text-green-700">All colour combinations meet WCAG AA.</p>
            ) : (
              <ul className="flex flex-col gap-2">
                {warnings.map((warning) => (
                  <li key={warning} className="rounded-md bg-amber-50 p-2 text-xs text-amber-900">
                    {warning}
                  </li>
                ))}
              </ul>
            )}
          </CardContent>
        </Card>
      </div>
    </div>
  );
}
