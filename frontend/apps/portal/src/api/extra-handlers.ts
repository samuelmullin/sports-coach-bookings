/** MSW handlers for the non-spec endpoints in `extras.ts`. */
import { HttpResponse, delay, type RequestHandler, http } from 'msw';
import type { PortalSettings } from '../features/shared/extras';

export const portalSettings: PortalSettings = {
  currency: 'CAD',
  timezone: 'America/Toronto',
};

export function getPortalExtraHandlers(): RequestHandler[] {
  return [
    http.get('/api/portal/context', async () => {
      await delay(20);
      return HttpResponse.json(portalSettings);
    }),
  ];
}
