import { useState } from 'react';
import { Link, useNavigate, useParams } from 'react-router-dom';
import { ArrowLeft, Download, FileText } from 'lucide-react';
import { useForm } from 'react-hook-form';
import { z } from 'zod';
import { zodResolver } from '@hookform/resolvers/zod';
import { useQueryClient } from '@tanstack/react-query';
import { applyApiFieldErrors } from '@scb/api-client';
import { Button, Card, CardContent, Checkbox, FormField, Input, useToast } from '@scb/ui';
import {
  playerWaiversQueryKey,
  useSignWaiver,
  useWaiverVersion,
  waiverSignaturePdfUrl,
  waiverVersionQueryKey,
  type WaiverSignatureResponse,
  type WaiverVersionResponse,
} from '../../api/endpoints';
import { body, errorMessage, responseData } from '../shared/api-utils';
import { QueryState } from '../shared/QueryState';
import { PageHeader } from '../shared/PageHeader';
import { readReturnTo } from '../shared/return-to';
import { Markdown } from '../shared/Markdown';
import { DocumentModal } from '../shared/DocumentModal';

const schema = z.object({
  signer_name_typed: z.string().min(1, 'Type your full name'),
  signer_relationship: z.string().optional(),
  consent_checkbox: z.boolean().refine((value) => value === true, {
    message: 'You must agree before signing',
  }),
});
type FormValues = z.infer<typeof schema>;

function WaiverPdfButton({ signatureId }: { signatureId: string }) {
  return (
    <Button asChild variant="outline">
      <a href={waiverSignaturePdfUrl(signatureId)} download>
        <Download className="h-4 w-4" aria-hidden="true" /> Download signed PDF
      </a>
    </Button>
  );
}

export function WaiverSignPage() {
  const { playerId = '', versionId = '' } = useParams<{
    playerId: string;
    versionId: string;
  }>();
  const navigate = useNavigate();
  const returnTo = readReturnTo();
  const queryClient = useQueryClient();
  const { toast } = useToast();
  const versionQuery = useWaiverVersion(versionId, {
    query: {
      queryKey: waiverVersionQueryKey(versionId),
      enabled: Boolean(versionId),
      retry: false,
    },
  });
  const version = body<WaiverVersionResponse>(versionQuery);
  const sign = useSignWaiver();
  const [signatureId, setSignatureId] = useState<string | null>(null);
  const [viewDocument, setViewDocument] = useState(false);

  const {
    register,
    handleSubmit,
    setError,
    setValue,
    watch,
    formState: { errors },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: { signer_name_typed: '', signer_relationship: '', consent_checkbox: false },
  });
  const consent = watch('consent_checkbox');

  const onSubmit = handleSubmit(async (values) => {
    if (!version) return;
    try {
      const result = await sign.mutateAsync({
        playerId,
        versionId,
        data: {
          content_sha256: version.content_sha256,
          signer_name_typed: values.signer_name_typed,
          signer_relationship: values.signer_relationship || null,
          consent_checkbox: true,
        },
      });
      // refetchType 'all': the player's waiver list is not mounted on this page, and
      // without an immediate refetch it briefly shows the pre-signing state (with a
      // "Read & sign" link that now 409s) when the customer goes back to it.
      await queryClient.invalidateQueries({
        queryKey: playerWaiversQueryKey(playerId),
        refetchType: 'all',
      });
      const signature = responseData<WaiverSignatureResponse>(result);
      setSignatureId(signature?.id ?? null);
      toast({ title: 'Waiver signed', variant: 'success' });
    } catch (error) {
      const applied = applyApiFieldErrors(error, {
        setError,
        fallbackField: 'consent_checkbox',
      });
      if (!applied.handled) toast({ title: errorMessage(error), variant: 'danger' });
    }
  });

  if (signatureId) {
    return (
      <div className="flex flex-col gap-4">
        <PageHeader title="Waiver signed" description="A copy is available to download." />
        <Card>
          <CardContent className="flex flex-wrap items-center gap-3 pt-4">
            <WaiverPdfButton signatureId={signatureId} />
            {returnTo ? <Button onClick={() => navigate(returnTo)}>Continue booking</Button> : null}
            <Button variant="outline" onClick={() => navigate(`/players/${playerId}`)}>
              Back to player
            </Button>
          </CardContent>
        </Card>
      </div>
    );
  }

  return (
    <div className="flex flex-col gap-4">
      <Button asChild variant="ghost" size="sm" className="self-start">
        <Link to={`/players/${playerId}`}>
          <ArrowLeft className="h-4 w-4" aria-hidden="true" /> Back to player
        </Link>
      </Button>

      <QueryState
        loading={versionQuery.isLoading}
        error={versionQuery.isError ? errorMessage(versionQuery.error) : undefined}
        onRetry={() => void versionQuery.refetch()}
      >
        {!version ? (
          <p className="text-sm text-muted-foreground">This waiver is not available.</p>
        ) : (
          <>
            <PageHeader title="Read and sign" description="Please read the full text below." />
            <Button
              type="button"
              variant="outline"
              size="sm"
              className="self-start"
              onClick={() => setViewDocument(true)}
            >
              <FileText className="h-4 w-4" aria-hidden="true" /> View document
            </Button>
            <Card>
              <CardContent className="pt-4">
                <Markdown
                  content={version.body_markdown}
                  className="flex flex-col gap-3 text-sm text-foreground"
                />
              </CardContent>
            </Card>

            <DocumentModal
              open={viewDocument}
              onOpenChange={setViewDocument}
              source={{ type: 'waiver', versionId, title: 'Waiver' }}
            />

            <form className="flex flex-col gap-4" onSubmit={onSubmit} noValidate>
              <FormField
                label="Type your full name"
                required
                error={errors.signer_name_typed?.message}
              >
                <Input autoComplete="name" {...register('signer_name_typed')} />
              </FormField>
              <FormField label="Relationship to player" error={errors.signer_relationship?.message}>
                <Input {...register('signer_relationship')} />
              </FormField>
              <FormField error={errors.consent_checkbox?.message}>
                <Checkbox
                  label="I have read and agree to this waiver on behalf of the player."
                  checked={consent}
                  onCheckedChange={(checked) => setValue('consent_checkbox', checked === true)}
                />
              </FormField>
              <div>
                <Button type="submit" disabled={sign.isPending}>
                  {sign.isPending ? 'Signing…' : 'Sign waiver'}
                </Button>
              </div>
            </form>
          </>
        )}
      </QueryState>
    </div>
  );
}
