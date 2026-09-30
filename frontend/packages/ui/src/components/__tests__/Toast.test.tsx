import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';
import { ToastProvider, useToast } from '../Toast';

function Trigger() {
  const { toast } = useToast();
  return (
    <button type="button" onClick={() => toast({ title: 'Saved', description: 'All good' })}>
      Fire toast
    </button>
  );
}

describe('Toast', () => {
  it('shows a toast when triggered', async () => {
    render(
      <ToastProvider>
        <Trigger />
      </ToastProvider>,
    );
    await userEvent.click(screen.getByRole('button', { name: 'Fire toast' }));
    expect(await screen.findByText('Saved')).toBeInTheDocument();
    expect(screen.getByText('All good')).toBeInTheDocument();
  });
});
