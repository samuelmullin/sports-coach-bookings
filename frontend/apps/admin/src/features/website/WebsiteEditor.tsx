import { useEffect, useState, type ReactNode } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import {
  Button,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  FileUpload,
  FormField,
  Input,
  Switch,
  useToast,
} from '@scb/ui';
import { ExternalLink, Plus, Trash2 } from 'lucide-react';
import {
  useCreateWebsiteUpload,
  usePublishWebsiteSite,
  useUpdateWebsiteSite,
  useWebsiteSite,
  websiteSiteQueryKey,
  type WebsiteSite,
  type WebsiteUpload,
} from '../../api/endpoints';
import { body, errorMessage, responseData } from '../shared/api-utils';
import type { WebsiteContent } from './types';

const empty: WebsiteContent = {
  hero: {},
  story: {},
  stats: [],
  features: [],
  testimonials: [],
  coaches: [],
  gallery: [],
  sponsors: [],
  faqs: [],
  contact: {},
  footer: {},
  seo: {},
};
const textarea = 'min-h-28 w-full rounded-md border border-border bg-background px-3 py-2 text-sm';

export function WebsiteEditor() {
  const query = useWebsiteSite();
  const update = useUpdateWebsiteSite();
  const publish = usePublishWebsiteSite();
  const upload = useCreateWebsiteUpload();
  const client = useQueryClient();
  const { toast } = useToast();
  const site = body<WebsiteSite>(query);
  const preview = (site as (WebsiteSite & { preview_content?: WebsiteContent }) | undefined)
    ?.preview_content;
  const [enabled, setEnabled] = useState(true);
  const [content, setContent] = useState<WebsiteContent>(empty);

  useEffect(() => {
    if (site) {
      setEnabled(site.enabled ?? true);
      setContent({ ...empty, ...(site.draft_content as WebsiteContent) });
    }
  }, [site]);

  const section = (name: keyof WebsiteContent, field: string, value: string) =>
    setContent((current) => ({
      ...current,
      [name]: { ...((current[name] as Record<string, string>) ?? {}), [field]: value },
    }));
  const setList = (name: keyof WebsiteContent, value: unknown[]) =>
    setContent((current) => ({ ...current, [name]: value }));
  const uploadFor = async (file: File) => {
    const result = await upload.mutateAsync({
      data: {
        filename: file.name,
        content_type: (file.type || 'image/jpeg') as never,
        byte_size: file.size,
      },
    });
    const value = responseData<WebsiteUpload>(result);
    if (!value) throw new Error('Upload could not be prepared');
    return {
      uploadUrl: value.upload_url,
      fileUrl: value.key,
      key: value.key,
      headers: value.headers as Record<string, string>,
    };
  };
  const persist = async () => {
    await update.mutateAsync({ data: { enabled, content: content as never } });
    await client.invalidateQueries({ queryKey: websiteSiteQueryKey() });
  };
  const save = async () => {
    try {
      await persist();
      toast({ title: 'Website draft saved', variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };
  const publishNow = async () => {
    try {
      await persist();
      await publish.mutateAsync();
      await client.invalidateQueries({ queryKey: websiteSiteQueryKey() });
      toast({ title: 'Website published', variant: 'success' });
    } catch (error) {
      toast({ title: errorMessage(error), variant: 'danger' });
    }
  };
  if (query.isLoading) return <p className="text-sm text-muted-foreground">Loading website…</p>;

  return (
    <div className="space-y-5">
      <Card>
        <CardContent className="flex flex-wrap items-center justify-between gap-4 pt-5">
          <div>
            <h2 className="font-semibold">Publishing</h2>
            <p className="text-sm text-muted-foreground">
              Save drafts freely, then publish when the site is ready.
            </p>
            {site?.published_at ? (
              <p className="mt-1 text-xs text-muted-foreground">
                Last published {new Date(site.published_at).toLocaleString()}
              </p>
            ) : null}
          </div>
          <div className="flex items-center gap-3">
            <Switch label="Website enabled" checked={enabled} onCheckedChange={setEnabled} />
            <Button variant="outline" onClick={() => void save()} disabled={update.isPending}>
              Save draft
            </Button>
            <Button onClick={() => void publishNow()} disabled={publish.isPending}>
              Publish
            </Button>
            {site?.published_at ? (
              <Button asChild variant="ghost">
                <a href="/" target="_blank" rel="noreferrer">
                  View site <ExternalLink className="h-4 w-4" />
                </a>
              </Button>
            ) : null}
          </div>
        </CardContent>
      </Card>
      <Card>
        <CardHeader>
          <CardTitle>Draft preview</CardTitle>
        </CardHeader>
        <CardContent>
          <div className="relative overflow-hidden rounded-xl bg-slate-950 px-6 py-12 text-white">
            {preview?.hero?.image_url ? (
              <img
                src={preview.hero.image_url}
                alt=""
                className="absolute inset-0 h-full w-full object-cover opacity-35"
              />
            ) : null}
            <div className="relative max-w-2xl">
              <p className="text-xs font-semibold uppercase tracking-[0.18em] text-white/70">
                {content.hero?.eyebrow}
              </p>
              <h2 className="mt-2 text-3xl font-bold">{content.hero?.title || 'Your headline'}</h2>
              <p className="mt-3 text-white/80">{content.hero?.body}</p>
            </div>
          </div>
          <p className="mt-2 text-xs text-muted-foreground">
            Text updates immediately. Save the draft to refresh uploaded images.
          </p>
        </CardContent>
      </Card>
      <div className="grid gap-5 xl:grid-cols-2">
        <Card>
          <CardHeader>
            <CardTitle>Announcement & hero</CardTitle>
          </CardHeader>
          <CardContent className="grid gap-4">
            <FormField label="Announcement bar">
              <Input
                value={content.announcement ?? ''}
                onChange={(e) => setContent({ ...content, announcement: e.target.value })}
              />
            </FormField>
            {[
              'eyebrow',
              'title',
              'body',
              'primary_cta_label',
              'primary_cta_url',
              'secondary_cta_label',
              'secondary_cta_url',
            ].map((field) => (
              <FormField key={field} label={field.replaceAll('_', ' ')}>
                <Input
                  value={content.hero?.[field] ?? ''}
                  onChange={(e) => section('hero', field, e.target.value)}
                />
              </FormField>
            ))}
            <FileUpload
              label="Upload hero image"
              accept="image/*"
              getPresignedUrl={uploadFor}
              onUploaded={(_file, result) => section('hero', 'image_key', result.key ?? '')}
            />
          </CardContent>
        </Card>
        <Card>
          <CardHeader>
            <CardTitle>Story</CardTitle>
          </CardHeader>
          <CardContent className="grid gap-4">
            {['eyebrow', 'title'].map((field) => (
              <FormField key={field} label={field}>
                <Input
                  value={content.story?.[field] ?? ''}
                  onChange={(e) => section('story', field, e.target.value)}
                />
              </FormField>
            ))}
            <FormField label="Story">
              <textarea
                aria-label="Story"
                className={textarea}
                value={content.story?.body ?? ''}
                onChange={(e) => section('story', 'body', e.target.value)}
              />
            </FormField>
            <FileUpload
              label="Upload story image"
              accept="image/*"
              getPresignedUrl={uploadFor}
              onUploaded={(_file, result) => section('story', 'image_key', result.key ?? '')}
            />
          </CardContent>
        </Card>
      </div>
      <SimpleList
        title="Statistics"
        items={content.stats ?? []}
        fields={['value', 'label']}
        onChange={(items) => setList('stats', items)}
      />
      <SimpleList
        title="Why choose us"
        items={content.features ?? []}
        fields={['title', 'body']}
        long={['body']}
        onChange={(items) => setList('features', items)}
      />
      <SimpleList
        title="Testimonials"
        items={content.testimonials ?? []}
        fields={['quote', 'name', 'detail']}
        long={['quote']}
        onChange={(items) => setList('testimonials', items)}
      />
      <SimpleList
        title="Coaches"
        items={content.coaches ?? []}
        fields={['name', 'title', 'bio', 'photo_key']}
        long={['bio']}
        uploadFor={uploadFor}
        onChange={(items) => setList('coaches', items)}
      />
      <Card>
        <CardHeader>
          <CardTitle>Gallery</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <FileUpload
            multiple
            label="Upload gallery images"
            accept="image/*"
            getPresignedUrl={uploadFor}
            onUploaded={(file, result) =>
              setList('gallery', [
                ...(content.gallery ?? []),
                { image_key: result.key, alt: file.name, caption: '' },
              ])
            }
          />
          <SimpleRows
            items={content.gallery ?? []}
            fields={['image_key', 'alt', 'caption']}
            uploadFor={uploadFor}
            onChange={(items) => setList('gallery', items)}
          />
        </CardContent>
      </Card>
      <SimpleList
        title="Sponsors"
        items={content.sponsors ?? []}
        fields={['name', 'description', 'url', 'logo_key']}
        long={['description']}
        uploadFor={uploadFor}
        onChange={(items) => setList('sponsors', items)}
      />
      <SimpleList
        title="FAQ"
        items={content.faqs ?? []}
        fields={['question', 'answer']}
        long={['answer']}
        onChange={(items) => setList('faqs', items)}
      />
      <div className="grid gap-5 xl:grid-cols-2">
        <FieldsCard
          title="Contact details"
          section="contact"
          fields={['intro', 'email', 'phone', 'address', 'hours']}
          content={content}
          onChange={section}
          long={['intro']}
        />
        <FieldsCard
          title="SEO & footer"
          section="seo"
          fields={['title', 'description', 'image_key']}
          content={content}
          onChange={section}
          long={['description']}
          uploadFor={uploadFor}
        >
          <FormField label="Footer tagline">
            <Input
              value={content.footer?.tagline ?? ''}
              onChange={(e) => section('footer', 'tagline', e.target.value)}
            />
          </FormField>
        </FieldsCard>
      </div>
    </div>
  );
}

function FieldsCard({
  title,
  section: name,
  fields,
  content,
  onChange,
  long = [],
  children,
  uploadFor,
}: {
  title: string;
  section: keyof WebsiteContent;
  fields: string[];
  content: WebsiteContent;
  onChange: (name: keyof WebsiteContent, field: string, value: string) => void;
  long?: string[];
  children?: ReactNode;
  uploadFor?: PresignImage;
}) {
  const values = (content[name] as Record<string, string>) ?? {};
  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
      </CardHeader>
      <CardContent className="grid gap-4">
        {fields.map((field) => (
          <FormField key={field} label={field.replaceAll('_', ' ')}>
            {field.endsWith('_key') && uploadFor ? (
              <AssetUpload
                value={values[field]}
                uploadFor={uploadFor}
                onChange={(value) => onChange(name, field, value)}
              />
            ) : long.includes(field) ? (
              <textarea
                aria-label={field.replaceAll('_', ' ')}
                className={textarea}
                value={values[field] ?? ''}
                onChange={(e) => onChange(name, field, e.target.value)}
              />
            ) : (
              <Input
                value={values[field] ?? ''}
                onChange={(e) => onChange(name, field, e.target.value)}
              />
            )}
          </FormField>
        ))}
        {children}
      </CardContent>
    </Card>
  );
}
function SimpleList({
  title,
  items,
  fields,
  long = [],
  onChange,
  uploadFor,
}: {
  title: string;
  items: Array<Record<string, string | undefined>>;
  fields: string[];
  long?: string[];
  onChange: (items: Array<Record<string, string | undefined>>) => void;
  uploadFor?: PresignImage;
}) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>{title}</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <SimpleRows
          items={items}
          fields={fields}
          long={long}
          uploadFor={uploadFor}
          onChange={onChange}
        />
        <Button type="button" variant="outline" onClick={() => onChange([...items, {}])}>
          <Plus className="h-4 w-4" /> Add item
        </Button>
      </CardContent>
    </Card>
  );
}
function SimpleRows({
  items,
  fields,
  long = [],
  onChange,
  uploadFor,
}: {
  items: Array<Record<string, string | undefined>>;
  fields: string[];
  long?: string[];
  onChange: (items: Array<Record<string, string | undefined>>) => void;
  uploadFor?: PresignImage;
}) {
  const update = (index: number, field: string, value: string) =>
    onChange(items.map((item, i) => (i === index ? { ...item, [field]: value } : item)));
  return (
    <div className="space-y-4">
      {items.map((item, index) => (
        <div key={index} className="grid gap-3 rounded-lg border border-border p-4">
          <div className="flex justify-end">
            <Button
              type="button"
              size="sm"
              variant="ghost"
              aria-label="Remove item"
              onClick={() => onChange(items.filter((_item, i) => i !== index))}
            >
              <Trash2 className="h-4 w-4" />
            </Button>
          </div>
          {fields.map((field) => (
            <FormField key={field} label={field.replaceAll('_', ' ')}>
              {field.endsWith('_key') && uploadFor ? (
                <AssetUpload
                  value={item[field]}
                  uploadFor={uploadFor}
                  onChange={(value) => update(index, field, value)}
                />
              ) : long.includes(field) ? (
                <textarea
                  aria-label={field.replaceAll('_', ' ')}
                  className={textarea}
                  value={item[field] ?? ''}
                  onChange={(e) => update(index, field, e.target.value)}
                />
              ) : (
                <Input
                  value={item[field] ?? ''}
                  onChange={(e) => update(index, field, e.target.value)}
                />
              )}
            </FormField>
          ))}
        </div>
      ))}
    </div>
  );
}

type PresignImage = (file: File) => Promise<{
  uploadUrl: string;
  fileUrl: string;
  key?: string;
  headers?: Record<string, string>;
}>;

function AssetUpload({
  value,
  uploadFor,
  onChange,
}: {
  value?: string;
  uploadFor: PresignImage;
  onChange: (value: string) => void;
}) {
  return (
    <div className="space-y-2">
      <FileUpload
        label={value ? 'Replace image' : 'Upload image'}
        accept="image/*"
        getPresignedUrl={uploadFor}
        onUploaded={(_file, result) => onChange(result.key ?? '')}
      />
      {value ? (
        <div className="flex items-center justify-between gap-3 text-xs text-muted-foreground">
          <span className="truncate">Image selected</span>
          <Button type="button" size="sm" variant="ghost" onClick={() => onChange('')}>
            Remove
          </Button>
        </div>
      ) : null}
    </div>
  );
}
