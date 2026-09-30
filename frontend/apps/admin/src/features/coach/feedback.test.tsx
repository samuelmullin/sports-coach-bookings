import { HttpResponse, http } from 'msw';
import { screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, describe, expect, it, vi } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../test/render';
import { FeedbackComposer } from './FeedbackComposer';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

function setupSkillTags() {
  server.use(
    http.get('/api/staff/feedback/skill_tags', () =>
      HttpResponse.json({
        data: [
          { id: 'tag-1', name: 'First touch', slug: 'first_touch', position: 0, active: true },
          { id: 'tag-2', name: 'Passing', slug: 'passing', position: 1, active: true },
        ],
      }),
    ),
  );
}

function renderComposer() {
  return renderWithProviders(
    <FeedbackComposer
      open
      onOpenChange={() => undefined}
      sessionId="session-today"
      playerId="player-1"
      playerName="Ava Striker"
    />,
  );
}

describe('coach feedback composer', () => {
  it('writes and shares feedback after confirmation', async () => {
    setupSkillTags();
    const post = vi.fn((_info: { request: Request }) =>
      HttpResponse.json(
        {
          id: 'feedback-new',
          session_id: 'session-today',
          player_id: 'player-1',
          coach_id: 'membership-1',
          body: 'Strong session',
          visibility: 'shared',
        },
        { status: 201 },
      ),
    );
    server.use(http.post('/api/staff/feedback', post));

    renderComposer();

    await userEvent.type(
      await screen.findByLabelText('Session note'),
      'Strong session on the ball',
    );
    await userEvent.click(screen.getByRole('button', { name: 'Share with family' }));

    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Share now' }));

    await waitFor(() => expect(post).toHaveBeenCalledTimes(1));
    const requestBody = await post.mock.calls[0][0].request.json();
    expect(requestBody).toMatchObject({
      session_id: 'session-today',
      player_id: 'player-1',
      body: 'Strong session on the ball',
      visibility: 'shared',
    });
    expect(await screen.findByText('Feedback shared with family')).toBeInTheDocument();
  });

  it('shows a field error returned by the server', async () => {
    setupSkillTags();
    server.use(
      http.post('/api/staff/feedback', () =>
        HttpResponse.json(
          {
            error: {
              code: 'invalid',
              message: 'Validation failed',
              details: { fields: { body: ['is too short'] } },
            },
          },
          { status: 422 },
        ),
      ),
    );

    renderComposer();

    await userEvent.type(await screen.findByLabelText('Session note'), 'ok');
    await userEvent.click(screen.getByRole('button', { name: 'Share with family' }));

    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Share now' }));

    expect(await screen.findByText('is too short')).toBeInTheDocument();
  });
});
