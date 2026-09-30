import { useState } from 'react';
import { createPortal } from 'react-dom';
import { Mail, Printer } from 'lucide-react';
import { Button, FormField, Input, Modal, useToast } from '@scb/ui';
import {
  portalDocumentQueryKey,
  useEmailPortalDocument,
  useEmailWaiverVersion,
  usePortalDocument,
  useWaiverVersion,
  waiverVersionQueryKey,
  type LegalDocumentResponse,
  type WaiverVersionResponse,
} from '../../api/endpoints';
import { useOptionalCustomerAuth } from '../../auth/customer-auth';
import { body, errorMessage } from '../shared/api-utils';
import { Markdown } from './Markdown';
import { QueryState } from './QueryState';

export type DocumentSource =
  { type: 'legal'; kind: string } | { type: 'waiver'; versionId: string; title?: string };

export interface DocumentModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  source: DocumentSource | null;
  /** Overrides the fetched document title. */
  title?: string;
}

/**
 * Renders a legal document or waiver body in a modal with Print and
 * "Email me a copy" actions.
 *
 * Print renders the document into a print-only region (`#document-print-region`,
 * portaled to `body`) and calls `window.print()`; a `@media print` rule hides
 * the rest of the application so the printed page is just the document.
 *
 * Email uses the signed-in customer's address when available, otherwise prompts
 * for one, and posts to the matching portal endpoint.
 */
export function DocumentModal({ open, onOpenChange, source, title }: DocumentModalProps) {
  const { customerUser } = useOptionalCustomerAuth() ?? {};
  const { toast } = useToast();
  const signedInEmail = customerUser?.email;
  const [email, setEmail] = useState('');
  const [emailError, setEmailError] = useState<string | undefined>();

  const legalKind = source?.type === 'legal' ? source.kind : '';
  const waiverId = source?.type === 'waiver' ? source.versionId : '';

  const legalQuery = usePortalDocument(legalKind, {
    query: {
      queryKey: portalDocumentQueryKey(legalKind),
      enabled: open && source?.type === 'legal',
      retry: false,
    },
  });
  const waiverQuery = useWaiverVersion(waiverId, {
    query: {
      queryKey: waiverVersionQueryKey(waiverId),
      enabled: open && source?.type === 'waiver',
      retry: false,
    },
  });

  const emailLegal = useEmailPortalDocument();
  const emailWaiver = useEmailWaiverVersion();

  const legalDoc = body<LegalDocumentResponse>(legalQuery);
  const waiverDoc = body<WaiverVersionResponse>(waiverQuery);

  const markdown =
    source?.type === 'legal'
      ? legalDoc?.body_markdown
      : source?.type === 'waiver'
        ? waiverDoc?.body_markdown
        : undefined;

  const resolvedTitle =
    title ??
    (source?.type === 'legal'
      ? legalDoc?.title
      : source?.type === 'waiver'
        ? (source.title ?? 'Waiver')
        : undefined);

  const query = source?.type === 'legal' ? legalQuery : waiverQuery;
  const isLoading = open && Boolean(source) && query.isLoading;
  const isError = query.isError;
  const isEmailing = emailLegal.isPending || emailWaiver.isPending;

  const onPrint = () => {
    window.print();
  };

  const onEmail = async () => {
    if (!source) return;
    const target = signedInEmail ?? email.trim();

    if (!target) {
      setEmailError('Enter an email address');
      return;
    }

    setEmailError(undefined);

    try {
      const data = { email: target };
      if (source.type === 'legal') {
        await emailLegal.mutateAsync({ kind: source.kind, data });
      } else {
        await emailWaiver.mutateAsync({ id: source.versionId, data });
      }
      toast({ title: `A copy was sent to ${target}`, variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  return (
    <Modal open={open} onOpenChange={onOpenChange} title={resolvedTitle ?? 'Document'} size="lg">
      <QueryState
        loading={isLoading}
        error={isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {markdown ? (
          <div className="flex flex-col gap-4">
            <div className="max-h-[55vh] overflow-y-auto pr-1">
              <Markdown
                content={markdown}
                className="flex flex-col gap-3 text-sm text-foreground"
              />
            </div>
            <div className="flex flex-col gap-3 border-t border-border pt-3">
              {signedInEmail ? (
                <p className="text-xs text-muted-foreground">
                  We&apos;ll email a copy to {signedInEmail}.
                </p>
              ) : (
                <FormField label="Email address" error={emailError}>
                  <Input
                    type="email"
                    value={email}
                    placeholder="you@example.com"
                    autoComplete="email"
                    onChange={(event) => {
                      setEmail(event.target.value);
                      setEmailError(undefined);
                    }}
                  />
                </FormField>
              )}
              <div className="flex flex-wrap justify-end gap-2">
                <Button type="button" variant="outline" onClick={onPrint}>
                  <Printer className="h-4 w-4" aria-hidden="true" /> Print
                </Button>
                <Button type="button" onClick={() => void onEmail()} disabled={isEmailing}>
                  <Mail className="h-4 w-4" aria-hidden="true" />
                  {signedInEmail ? 'Email me a copy' : 'Email a copy'}
                </Button>
              </div>
            </div>
          </div>
        ) : (
          <p className="text-sm text-muted-foreground">This document is not available.</p>
        )}
      </QueryState>

      {open && markdown
        ? createPortal(
            <div id="document-print-region" className="hidden print:block">
              <h1 className="text-2xl font-bold">{resolvedTitle}</h1>
              <Markdown
                content={markdown}
                className="flex flex-col gap-3 text-sm text-foreground"
              />
            </div>,
            document.body,
          )
        : null}
    </Modal>
  );
}
