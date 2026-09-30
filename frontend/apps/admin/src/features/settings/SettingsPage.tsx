import { TabsView } from '@scb/ui';
import { useSearchParams } from 'react-router-dom';
import { PageHeader } from '../shared/PageHeader';
import { GeneralSettingsForm } from './GeneralSettingsForm';
import { TaxRatesSection } from './TaxRatesSection';
import { ReminderTimingForm } from './ReminderTimingForm';
import { BrandingEditor } from '../branding/BrandingEditor';
import { PaymentsPanel } from '../payments/PaymentsPanel';

export function SettingsPage() {
  const [params, setParams] = useSearchParams();
  const tab = params.get('tab') ?? 'general';

  return (
    <div className="flex flex-col gap-4">
      <PageHeader title="Settings" description="Business details, tax, branding and payments." />
      <TabsView
        aria-label="Settings sections"
        value={tab}
        onValueChange={(value) => setParams({ tab: value }, { replace: true })}
        items={[
          { value: 'general', label: 'General', content: <GeneralSettingsForm /> },
          { value: 'tax', label: 'Tax', content: <TaxRatesSection /> },
          { value: 'reminders', label: 'Reminders', content: <ReminderTimingForm /> },
          { value: 'branding', label: 'Branding', content: <BrandingEditor /> },
          { value: 'payments', label: 'Payments', content: <PaymentsPanel /> },
        ]}
      />
    </div>
  );
}
