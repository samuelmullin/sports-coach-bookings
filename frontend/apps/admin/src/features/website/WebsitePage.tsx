import { TabsView } from '@scb/ui';
import { useSearchParams } from 'react-router-dom';
import { PageHeader } from '../shared/PageHeader';
import { WebsiteEditor } from './WebsiteEditor';
import { WebsiteInbox } from './WebsiteInbox';

export function WebsitePage() {
  const [params, setParams] = useSearchParams();
  const tab = params.get('tab') ?? 'editor';
  return (
    <div className="flex flex-col gap-4">
      <PageHeader
        title="Website"
        description="Build, preview and publish the public website that shares your live catalog and schedule."
      />
      <TabsView
        aria-label="Website sections"
        value={tab}
        onValueChange={(value) => setParams({ tab: value }, { replace: true })}
        items={[
          { value: 'editor', label: 'Editor', content: <WebsiteEditor /> },
          { value: 'inbox', label: 'Contact inbox', content: <WebsiteInbox /> },
        ]}
      />
    </div>
  );
}
