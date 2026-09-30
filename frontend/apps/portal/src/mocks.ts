export async function enableMocks(): Promise<void> {
  const { worker } = await import('@scb/mocks/browser');
  const { getPortalExtraHandlers } = await import('./api/extra-handlers');
  await worker.start({
    onUnhandledRequest: 'bypass',
    quiet: true,
  });
  // App-local handlers for endpoints not in the OpenAPI spec.
  worker.use(...getPortalExtraHandlers());
}

export function mocksEnabled(): boolean {
  return import.meta.env.VITE_USE_MOCKS === 'true';
}
