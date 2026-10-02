import { lazy, type ComponentType, type LazyExoticComponent } from 'react';

type AnyComponent = ComponentType<any>;

/**
 * `React.lazy` for a module's *named* export, so route components keep their
 * named exports: `lazyNamed(() => import('./OrdersPage'), 'OrdersPage')`.
 * Modules may export other values besides components; only `name` must be one.
 */
export function lazyNamed<M, K extends keyof M & string>(
  factory: () => Promise<M>,
  name: M[K] extends AnyComponent ? K : never,
): LazyExoticComponent<Extract<M[K], AnyComponent>> {
  return lazy(() =>
    factory().then((module) => ({ default: module[name] as Extract<M[K], AnyComponent> })),
  );
}
