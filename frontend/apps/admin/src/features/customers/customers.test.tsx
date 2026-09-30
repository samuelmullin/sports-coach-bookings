import { HttpResponse, http } from 'msw';
import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { afterAll, afterEach, beforeAll, describe, expect, it } from 'vitest';
import { server } from '@scb/mocks/server';
import { renderWithProviders } from '../../test/render';
import { MedicalReveal } from './MedicalReveal';

beforeAll(() => server.listen({ onUnhandledRequest: 'bypass' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

describe('MedicalReveal', () => {
  it('reveals medical info after an explicit action and shows the audit notice', async () => {
    server.use(
      http.get('/api/staff/players/:id/medical', () =>
        HttpResponse.json({
          has_medical_info: true,
          player_id: 'player-1',
          allergies: 'Peanuts',
          conditions: 'Asthma',
          medications: 'Inhaler',
          notes: 'Carries inhaler',
        }),
      ),
    );

    renderWithProviders(<MedicalReveal playerId="player-1" hasMedicalInfo />);

    expect(screen.queryByText('Peanuts')).not.toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: /Reveal medical info/ }));

    expect(await screen.findByText('Peanuts')).toBeInTheDocument();
    expect(screen.getByText(/recorded in the audit log/i)).toBeInTheDocument();
  });
});
