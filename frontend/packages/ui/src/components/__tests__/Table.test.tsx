import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { Table, type TableColumn } from '../Table';
import { CursorPagination } from '../CursorPagination';

interface Row {
  id: string;
  name: string;
  players: number;
}

const columns: TableColumn<Row>[] = [
  { key: 'name', header: 'Name', sortable: true, cell: (row) => row.name },
  {
    key: 'players',
    header: 'Players',
    sortable: true,
    align: 'right',
    cell: (row) => row.players,
  },
];

const rows: Row[] = [
  { id: '1', name: 'Soccer 101', players: 8 },
  { id: '2', name: 'Advanced', players: 4 },
];

describe('Table', () => {
  it('renders rows and handles row clicks', async () => {
    const onRowClick = vi.fn();
    render(
      <Table columns={columns} data={rows} rowKey={(row) => row.id} onRowClick={onRowClick} />,
    );
    await userEvent.click(screen.getByText('Soccer 101'));
    expect(onRowClick).toHaveBeenCalledWith(rows[0]);
  });

  it('requests a sort when a sortable header is clicked', async () => {
    const onSortChange = vi.fn();
    render(
      <Table columns={columns} data={rows} rowKey={(row) => row.id} onSortChange={onSortChange} />,
    );
    await userEvent.click(screen.getByRole('button', { name: /Players/ }));
    expect(onSortChange).toHaveBeenCalledWith({ key: 'players', direction: 'asc' });
  });

  it('toggles sort direction when already sorted', async () => {
    const onSortChange = vi.fn();
    render(
      <Table
        columns={columns}
        data={rows}
        rowKey={(row) => row.id}
        sort={{ key: 'players', direction: 'asc' }}
        onSortChange={onSortChange}
      />,
    );
    await userEvent.click(screen.getByRole('button', { name: /Players/ }));
    expect(onSortChange).toHaveBeenCalledWith({ key: 'players', direction: 'desc' });
  });

  it('shows the empty state when there is no data', () => {
    render(
      <Table
        columns={columns}
        data={[]}
        rowKey={(row) => row.id}
        emptyState={<span>Nothing here yet</span>}
      />,
    );
    expect(screen.getByText('Nothing here yet')).toBeInTheDocument();
  });
});

describe('CursorPagination', () => {
  it('disables both directions when there is no cursor', () => {
    render(<CursorPagination />);
    expect(screen.getByRole('button', { name: /Previous/ })).toBeDisabled();
    expect(screen.getByRole('button', { name: /Next/ })).toBeDisabled();
  });

  it('invokes the callbacks when enabled', async () => {
    const onNext = vi.fn();
    render(<CursorPagination hasNext onNext={onNext} />);
    await userEvent.click(screen.getByRole('button', { name: /Next/ }));
    expect(onNext).toHaveBeenCalled();
  });
});
