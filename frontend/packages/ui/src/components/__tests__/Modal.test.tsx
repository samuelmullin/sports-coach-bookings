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

  it('traps focus while open and restores focus to the opener when closed', async () => {
    render(<ModalHarness />);
    const opener = screen.getByRole('button', { name: 'Open modal' });
    await userEvent.click(opener);

    const close = screen.getByRole('button', { name: 'Close' });
    expect(close).toHaveFocus();

    await userEvent.tab();
    expect(close).toHaveFocus();

    await userEvent.keyboard('{Escape}');
    expect(opener).toHaveFocus();
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

// Regression: long forms in a Modal/Drawer overflowed the viewport with no way to
// scroll to the action buttons (found by the browser e2e suite at 1280x720).
// jsdom has no layout, so assert the structure that makes scrolling possible:
// a flex-column container (bounded height) around a min-h-0 scrollable body.
describe('scrollable dialog content', () => {
  it.each([
    [
      'Modal',
      <Modal key="m" open onOpenChange={() => {}} title="T">
        <p>Body</p>
      </Modal>,
    ],
    [
      'Drawer',
      <Drawer key="d" open onOpenChange={() => {}} title="T">
        <p>Body</p>
      </Drawer>,
    ],
  ])('%s keeps its body scrollable inside a bounded flex column', (_name, element) => {
    render(element);
    const dialog = screen.getByRole('dialog');
    expect(dialog).toHaveClass('flex', 'flex-col');
    const body = screen.getByText('Body').parentElement as HTMLElement;
    expect(body).toHaveClass('overflow-y-auto', 'min-h-0', 'flex-1');
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
