import { useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { Search } from 'lucide-react';
import {
  Badge,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  EmptyState,
  Input,
  Table,
  TabsView,
} from '@scb/ui';
import { useCustomers, useHouseholds } from '../../api/endpoints';
import { errorMessage, listItems } from '../shared/api-utils';
import { PageHeader } from '../shared/PageHeader';
import { QueryState } from '../shared/QueryState';

function HouseholdSearch() {
  const [q, setQ] = useState('');
  const query = useHouseholds({ q: q || undefined, limit: 25 });
  const households = listItems<{ id?: string; name?: string | null }>(query);
  const navigate = useNavigate();

  return (
    <div className="flex flex-col gap-3">
      <div className="relative max-w-sm">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          aria-label="Search households"
          className="pl-9"
          placeholder="Search by household name or email"
          value={q}
          onChange={(event) => setQ(event.target.value)}
        />
      </div>
      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {households.length === 0 ? (
          <EmptyState title="No households found" description="Try a different search." />
        ) : (
          <Table
            caption="Households"
            rowKey={(row) => row.id ?? ''}
            onRowClick={(row) => row.id && navigate(`/households/${row.id}`)}
            columns={[
              {
                key: 'name',
                header: 'Household',
                cell: (row) => (
                  <Link
                    className="font-medium text-primary hover:underline"
                    to={`/households/${row.id}`}
                  >
                    {row.name ?? 'Unnamed household'}
                  </Link>
                ),
              },
            ]}
            data={households}
          />
        )}
      </QueryState>
    </div>
  );
}

function CustomerSearch() {
  const [q, setQ] = useState('');
  const query = useCustomers({ q: q || undefined, limit: 25 });
  const customers = listItems<{
    id?: string;
    first_name?: string;
    last_name?: string;
    email?: string;
    active?: boolean;
    confirmed?: boolean;
  }>(query);
  const navigate = useNavigate();

  return (
    <div className="flex flex-col gap-3">
      <div className="relative max-w-sm">
        <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-muted-foreground" />
        <Input
          aria-label="Search customers"
          className="pl-9"
          placeholder="Search by name, email or phone"
          value={q}
          onChange={(event) => setQ(event.target.value)}
        />
      </div>
      <QueryState
        loading={query.isLoading}
        error={query.isError ? errorMessage(query.error) : undefined}
        onRetry={() => void query.refetch()}
      >
        {customers.length === 0 ? (
          <EmptyState title="No customers found" description="Try a different search." />
        ) : (
          <Table
            caption="Customers"
            rowKey={(row) => row.id ?? ''}
            onRowClick={(row) => row.id && navigate(`/customers/${row.id}`)}
            columns={[
              {
                key: 'name',
                header: 'Name',
                cell: (row) => (
                  <Link
                    className="font-medium text-primary hover:underline"
                    to={`/customers/${row.id}`}
                  >
                    {[row.first_name, row.last_name].filter(Boolean).join(' ') || '—'}
                  </Link>
                ),
              },
              { key: 'email', header: 'Email', cell: (row) => row.email ?? '—' },
              {
                key: 'status',
                header: 'Status',
                cell: (row) => (
                  <Badge variant={row.active ? 'success' : 'outline'}>
                    {row.active ? 'Active' : 'Inactive'}
                  </Badge>
                ),
              },
            ]}
            data={customers}
          />
        )}
      </QueryState>
    </div>
  );
}

export function CustomersPage() {
  return (
    <div className="flex flex-col gap-4">
      <PageHeader title="Customers" description="Search households and customer accounts." />
      <Card>
        <CardHeader>
          <CardTitle>Find a customer</CardTitle>
        </CardHeader>
        <CardContent>
          <TabsView
            aria-label="Customer search"
            items={[
              { value: 'households', label: 'Households', content: <HouseholdSearch /> },
              { value: 'customers', label: 'Customer accounts', content: <CustomerSearch /> },
            ]}
          />
        </CardContent>
      </Card>
    </div>
  );
}
