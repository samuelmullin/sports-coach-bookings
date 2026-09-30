import * as ToastPrimitive from '@radix-ui/react-toast';
import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react';
import { X } from 'lucide-react';
import { cn } from '../lib/cn';

export type ToastVariant = 'default' | 'success' | 'danger';

export interface ToastMessage {
  id: string;
  title: string;
  description?: string;
  variant?: ToastVariant;
  duration?: number;
  action?: ReactNode;
}

export interface ToastOptions {
  title: string;
  description?: string;
  variant?: ToastVariant;
  duration?: number;
  action?: ReactNode;
}

interface ToastContextValue {
  toast: (options: ToastOptions) => string;
  dismiss: (id: string) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

export function useToast(): ToastContextValue {
  const context = useContext(ToastContext);
  if (!context) {
    throw new Error('useToast must be used within a <ToastProvider>');
  }
  return context;
}

const VARIANT_CLASS: Record<ToastVariant, string> = {
  default: 'border-border bg-surface text-foreground',
  success: 'border-green-300 bg-green-50 text-green-900',
  danger: 'border-red-300 bg-red-50 text-red-900',
};

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<ToastMessage[]>([]);

  const dismiss = useCallback((id: string) => {
    setToasts((current) => current.filter((toastItem) => toastItem.id !== id));
  }, []);

  const toast = useCallback((options: ToastOptions) => {
    const id = `toast-${Date.now()}-${Math.random().toString(36).slice(2)}`;
    setToasts((current) => [...current, { id, variant: 'default', ...options }]);
    return id;
  }, []);

  const value = useMemo(() => ({ toast, dismiss }), [toast, dismiss]);

  return (
    <ToastContext.Provider value={value}>
      <ToastPrimitive.Provider swipeDirection="right">
        {children}
        {toasts.map((toastItem) => (
          <ToastPrimitive.Root
            key={toastItem.id}
            open
            duration={toastItem.duration ?? 5000}
            onOpenChange={(open) => {
              if (!open) dismiss(toastItem.id);
            }}
            role={toastItem.variant === 'danger' ? 'alert' : 'status'}
            className={cn(
              'pointer-events-auto flex w-full items-start justify-between gap-3 rounded-md border p-3 shadow-lg',
              VARIANT_CLASS[toastItem.variant ?? 'default'],
            )}
          >
            <div className="flex flex-col gap-0.5">
              <ToastPrimitive.Title className="text-sm font-semibold">
                {toastItem.title}
              </ToastPrimitive.Title>
              {toastItem.description ? (
                <ToastPrimitive.Description className="text-sm opacity-90">
                  {toastItem.description}
                </ToastPrimitive.Description>
              ) : null}
              {toastItem.action}
            </div>
            <ToastPrimitive.Close
              aria-label="Dismiss"
              className="rounded p-1 opacity-70 hover:opacity-100 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </ToastPrimitive.Close>
          </ToastPrimitive.Root>
        ))}
        <ToastPrimitive.Viewport className="fixed bottom-0 right-0 z-[100] m-4 flex max-h-screen w-full max-w-sm flex-col gap-2 outline-none" />
      </ToastPrimitive.Provider>
    </ToastContext.Provider>
  );
}
