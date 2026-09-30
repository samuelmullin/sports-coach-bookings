import { setupWorker } from 'msw/browser';
import { getSportsCoachBookingsAPIMock } from './generated/endpoints.msw';
import { getMockHandlers } from './handlers';

export const handlers = [...getMockHandlers(), ...getSportsCoachBookingsAPIMock()];

export const worker = setupWorker(...handlers);
