import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { Button, Card, CardContent, FormField, Input } from '@scb/ui';
import { useSubmitWebsiteContact } from '../../api/endpoints';
import { errorMessage } from '../shared/api-utils';
import { MarketingPage } from './MarketingPage';
import { useWebsiteContent } from './useWebsiteContent';

const schema = z.object({
  name: z.string().min(1, 'Name is required'),
  email: z.string().email('Enter a valid email'),
  phone: z.string(),
  company: z.string(),
  subject: z.string(),
  message: z.string().min(10, 'Please include a little more detail'),
});
type Values = z.infer<typeof schema>;

export function ContactPage() {
  const details = useWebsiteContent()?.contact;
  const submit = useSubmitWebsiteContact();
  const [sent, setSent] = useState(false);
  const [failure, setFailure] = useState<string>();
  const {
    register,
    handleSubmit,
    formState: { errors },
  } = useForm<Values>({
    resolver: zodResolver(schema),
    defaultValues: { name: '', email: '', phone: '', company: '', subject: '', message: '' },
  });
  const onSubmit = handleSubmit(async (values) => {
    setFailure(undefined);
    try {
      await submit.mutateAsync({ data: values });
      setSent(true);
    } catch (error) {
      setFailure(errorMessage(error));
    }
  });
  return (
    <MarketingPage
      eyebrow="Contact"
      title="Get in touch."
      intro={
        details?.intro ??
        'Questions about programs, booking, camps, or private training? Send us a note.'
      }
    >
      <div className="grid gap-6 lg:grid-cols-[1.4fr_1fr]">
        {sent ? (
          <Card>
            <CardContent className="pt-6">
              <h2 className="text-xl font-semibold">Thanks—we received your message.</h2>
              <p className="mt-2 text-muted-foreground">
                The coaching team will get back to you soon.
              </p>
            </CardContent>
          </Card>
        ) : (
          <Card>
            <CardContent className="pt-6">
              <form className="grid gap-4" onSubmit={onSubmit} noValidate>
                <div className="grid gap-4 sm:grid-cols-2">
                  <FormField label="Name" error={errors.name?.message}>
                    <Input {...register('name')} />
                  </FormField>
                  <FormField label="Email" error={errors.email?.message}>
                    <Input type="email" {...register('email')} />
                  </FormField>
                  <FormField label="Phone (optional)">
                    <Input {...register('phone')} />
                  </FormField>
                  <FormField label="Company (optional)">
                    <Input {...register('company')} />
                  </FormField>
                </div>
                <FormField label="Subject">
                  <Input {...register('subject')} />
                </FormField>
                <FormField
                  id="website-contact-message"
                  label="Message"
                  error={errors.message?.message}
                >
                  <textarea
                    id="website-contact-message"
                    className="min-h-36 rounded-md border border-border bg-background px-3 py-2 text-sm"
                    {...register('message')}
                  />
                </FormField>
                <Button type="submit" disabled={submit.isPending} className="self-start">
                  {submit.isPending ? 'Sending…' : 'Send message'}
                </Button>
                {failure ? (
                  <p role="alert" className="text-sm text-danger">
                    {failure}
                  </p>
                ) : null}
              </form>
            </CardContent>
          </Card>
        )}
        <aside className="space-y-5 rounded-2xl bg-surface p-6">
          <h2 className="text-lg font-semibold">Reach us directly</h2>
          {details?.email ? (
            <p>
              <span className="block text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                Email
              </span>
              <a className="text-primary hover:underline" href={`mailto:${details.email}`}>
                {details.email}
              </a>
            </p>
          ) : null}
          {details?.phone ? (
            <p>
              <span className="block text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                Phone
              </span>
              <a className="text-primary hover:underline" href={`tel:${details.phone}`}>
                {details.phone}
              </a>
            </p>
          ) : null}
          {details?.address ? (
            <p>
              <span className="block text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                Location
              </span>
              {details.address}
            </p>
          ) : null}
          {details?.hours ? (
            <p>
              <span className="block text-xs font-semibold uppercase tracking-wide text-muted-foreground">
                Hours
              </span>
              {details.hours}
            </p>
          ) : null}
        </aside>
      </div>
    </MarketingPage>
  );
}
