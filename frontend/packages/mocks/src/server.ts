import { setupServer } from 'msw/node';
import { getSportsCoachBookingsAPIMock } from './generated/endpoints.msw';
import { getMockHandlers } from './handlers';

export const handlers = [...getMockHandlers(), ...getSportsCoachBookingsAPIMock()];

export const server = setupServer(...handlers);
