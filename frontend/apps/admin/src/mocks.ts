export async function enableMocks(): Promise<void> {
  const { worker } = await import('@scb/mocks/browser');
  const { getExtraMockHandlers } = await import('./api/extra-handlers');
  await worker.start({
    onUnhandledRequest: 'bypass',
    quiet: true,
    serviceWorker: { url: '/admin/mockServiceWorker.js' },
  });
  // App-local handlers for endpoints not yet in the OpenAPI spec.
  worker.use(...getExtraMockHandlers());
}

export function mocksEnabled(): boolean {
  return import.meta.env.VITE_USE_MOCKS === 'true';
}
