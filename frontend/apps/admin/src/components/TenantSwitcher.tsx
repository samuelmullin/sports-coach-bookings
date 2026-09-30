import { Select } from '@scb/ui';
import { useStaffAuth } from '../auth/staff-auth';

export function TenantSwitcher() {
  const { memberships, membership, buildTenantUrl } = useStaffAuth();

  if (memberships.length <= 1) {
    return (
      <span className="text-sm font-medium" data-testid="tenant-name">
        {membership?.tenant?.name ?? 'Workspace'}
      </span>
    );
  }

  return (
    <Select
      aria-label="Switch tenant"
      className="h-9 w-48"
      value={membership?.tenant?.slug}
      options={memberships.map((item) => ({
        value: item.tenant?.slug ?? '',
        label: item.tenant?.name ?? item.tenant?.slug ?? 'Tenant',
      }))}
      onValueChange={(slug) => {
        window.location.assign(buildTenantUrl(slug));
      }}
    />
  );
}
