import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { useState } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { Modal, Drawer } from '../Modal';
import { ConfirmDialog } from '../ConfirmDialog';

function ModalHarness() {
  const [open, setOpen] = useState(false);
  return (
    <>
      <button type="button" onClick={() => setOpen(true)}>
        Open modal
      </button>
      <Modal open={open} onOpenChange={setOpen} title="Edit player">
        <p>Modal body</p>
      </Modal>
    </>
  );
}

describe('Modal', () => {
  it('opens, shows a title and body, and closes with Escape', async () => {
    render(<ModalHarness />);
    await userEvent.click(screen.getByRole('button', { name: 'Open modal' }));
    expect(screen.getByRole('dialog')).toBeInTheDocument();
    expect(screen.getByText('Edit player')).toBeInTheDocument();
    await userEvent.keyboard('{Escape}');
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument();
  });
});

describe('Drawer', () => {
  it('renders a dialog with the requested title', () => {
    render(
      <Drawer open onOpenChange={() => {}} title="Filters">
        <p>Drawer body</p>
      </Drawer>,
    );
    expect(screen.getByRole('dialog')).toBeInTheDocument();
    expect(screen.getByText('Filters')).toBeInTheDocument();
  });
});

describe('ConfirmDialog', () => {
  it('calls onConfirm when the confirm button is pressed', async () => {
    const onConfirm = vi.fn();
    render(
      <ConfirmDialog
        open
        onOpenChange={() => {}}
        title="Delete session?"
        confirmLabel="Delete"
        destructive
        onConfirm={onConfirm}
      />,
    );
    await userEvent.click(screen.getByRole('button', { name: 'Delete' }));
    expect(onConfirm).toHaveBeenCalled();
  });
});
