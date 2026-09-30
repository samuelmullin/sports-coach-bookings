import { useEffect, useState } from 'react';
import { useNavigate, useParams } from 'react-router-dom';
import {
  Badge,
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  ConfirmDialog,
  EmptyState,
  Table,
  Textarea,
  useToast,
} from '@scb/ui';
import {
  useCreateWaiverVersion,
  usePublishWaiverVersion,
  useUpdateWaiverVersion,
  useWaiverSignatures,
  useWaiverTemplate,
  useWaiverVersions,
  type WaiverVersionResponse,
  waiverSignaturePdfUrl,
} from '../../api/endpoints';
import { body, errorMessage, listItems } from '../shared/api-utils';
import { MarkdownPreview } from '../shared/MarkdownPreview';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';

function statusVariant(status: string) {
  if (status === 'published') return 'success' as const;
  if (status === 'draft') return 'warning' as const;
  return 'outline' as const;
}

export function WaiverEditorPage() {
  const { templateId = '' } = useParams();
  const navigate = useNavigate();
  const { toast } = useToast();

  const templateQuery = useWaiverTemplate(templateId);
  const versionsQuery = useWaiverVersions(templateId);
  const signaturesQuery = useWaiverSignatures({ template_id: templateId, limit: 25 });
  const createVersion = useCreateWaiverVersion();
  const updateVersion = useUpdateWaiverVersion();
  const publishVersion = usePublishWaiverVersion();

  const template = body<{
    id: string;
    name: string;
    require_resign_on_new_version?: boolean;
  }>(templateQuery);
  const versions = listItems<WaiverVersionResponse>(versionsQuery);
  const signatures = listItems<{
    id: string;
    signer_name_typed: string;
    player_id: string;
    signed_at?: string;
  }>(signaturesQuery);

  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [bodyText, setBodyText] = useState('');
  const [publishOpen, setPublishOpen] = useState(false);

  const selected = versions.find((version) => version.id === selectedId) ?? versions[0];

  useEffect(() => {
    if (selected) {
      setSelectedId(selected.id);
      setBodyText(selected.body_markdown);
    }
  }, [selected]);

  const isDraft = selected?.status === 'draft';

  const save = async (publish: boolean) => {
    try {
      let versionId: string | undefined = selected?.id;
      if (!selected || selected.status === 'published') {
        const result = await createVersion.mutateAsync({
          templateId,
          data: { body_markdown: bodyText },
        });
        const created = (result as { data?: WaiverVersionResponse }).data;
        versionId = created?.id;
        if (publish && versionId) {
          await publishVersion.mutateAsync({ id: versionId });
        }
      } else if (isDraft) {
        await updateVersion.mutateAsync({ id: selected.id, data: { body_markdown: bodyText } });
        if (publish) await publishVersion.mutateAsync({ id: selected.id });
      }
      toast({ title: publish ? 'Version published' : 'Draft saved', variant: 'success' });
      setPublishOpen(false);
      void versionsQuery.refetch();
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };

  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title={template?.name ?? 'Waiver'}
        description="Edit the waiver body and publish new versions."
        actions={
          <Button variant="outline" onClick={() => navigate('/waivers')}>
            Back to waivers
          </Button>
        }
      />

      <QueryState
        loading={templateQuery.isLoading || versionsQuery.isLoading}
        error={templateQuery.isError ? errorMessage(templateQuery.error) : undefined}
        onRetry={() => void templateQuery.refetch()}
      >
        <div className="flex flex-col gap-4">
          <Card>
            <CardHeader>
              <CardTitle>Versions</CardTitle>
            </CardHeader>
            <CardContent className="flex flex-wrap gap-2">
              {versions.length === 0 ? (
                <p className="text-sm text-muted-foreground">No versions yet.</p>
              ) : (
                versions.map((version) => (
                  <button
                    key={version.id}
                    type="button"
                    onClick={() => {
                      setSelectedId(version.id);
                      setBodyText(version.body_markdown);
                    }}
                    className={`rounded-md border px-3 py-1.5 text-sm ${
                      selected?.id === version.id ? 'border-primary bg-muted' : 'border-border'
                    }`}
                  >
                    v{version.version}{' '}
                    <Badge variant={statusVariant(version.status)}>{version.status}</Badge>
                  </button>
                ))
              )}
              <Button
                variant="outline"
                size="sm"
                onClick={() => {
                  setSelectedId(null);
                  setBodyText(selected?.body_markdown ?? '');
                }}
              >
                New version
              </Button>
            </CardContent>
          </Card>

          <div className="grid gap-4 lg:grid-cols-2">
            <Card>
              <CardHeader>
                <CardTitle>Markdown</CardTitle>
              </CardHeader>
              <CardContent className="flex flex-col gap-3">
                <Textarea
                  aria-label="Waiver body"
                  className="min-h-[320px] font-mono text-xs"
                  value={bodyText}
                  onChange={(event) => setBodyText(event.target.value)}
                  readOnly={selected?.status === 'published'}
                />
                <div className="flex justify-end gap-2">
                  <Button
                    variant="outline"
                    onClick={() => void save(false)}
                    disabled={selected?.status === 'published' || createVersion.isPending}
                  >
                    Save draft
                  </Button>
                  <Button onClick={() => setPublishOpen(true)} disabled={createVersion.isPending}>
                    Publish new version
                  </Button>
                </div>
              </CardContent>
            </Card>

            <Card>
              <CardHeader>
                <CardTitle>Preview</CardTitle>
              </CardHeader>
              <CardContent>
                <div className="max-h-[420px] overflow-auto rounded-md border border-border p-3">
                  <MarkdownPreview markdown={bodyText} />
                </div>
              </CardContent>
            </Card>
          </div>

          <Card>
            <CardHeader>
              <CardTitle>Signatures</CardTitle>
            </CardHeader>
            <CardContent>
              {signatures.length === 0 ? (
                <EmptyState title="No signatures" description="Signed waivers appear here." />
              ) : (
                <Table
                  caption="Signatures for this template"
                  rowKey={(row) => row.id}
                  columns={[
                    { key: 'signer', header: 'Signed by', cell: (row) => row.signer_name_typed },
                    { key: 'player', header: 'Player', cell: (row) => row.player_id },
                    {
                      key: 'signed',
                      header: 'Signed',
                      cell: (row) =>
                        row.signed_at ? new Date(row.signed_at).toLocaleString() : '—',
                    },
                    {
                      key: 'pdf',
                      header: 'PDF',
                      align: 'right',
                      cell: (row) => (
                        <a
                          className="text-sm font-medium text-primary hover:underline"
                          href={waiverSignaturePdfUrl(row.id)}
                          target="_blank"
                          rel="noreferrer"
                        >
                          Download
                        </a>
                      ),
                    },
                  ]}
                  data={signatures}
                />
              )}
            </CardContent>
          </Card>
        </div>
      </QueryState>

      <ConfirmDialog
        open={publishOpen}
        onOpenChange={setPublishOpen}
        title="Publish new version?"
        description={
          template?.require_resign_on_new_version
            ? 'Publishing will require every customer to re-sign this waiver before booking. Existing signatures remain on file for the old version.'
            : 'Publishing makes this version current. Customers who signed an older version will not need to re-sign.'
        }
        confirmLabel="Publish"
        loading={publishVersion.isPending || createVersion.isPending}
        onConfirm={() => void save(true)}
      />
    </div>
  );
}
