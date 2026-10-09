import * as DialogPrimitive from '@radix-ui/react-dialog';
import { X } from 'lucide-react';
import { useRef, type ReactNode } from 'react';
import { cn } from '../lib/cn';

export interface ModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  title: ReactNode;
  description?: ReactNode;
  children?: ReactNode;
  footer?: ReactNode;
  size?: 'sm' | 'md' | 'lg';
  closeLabel?: string;
  className?: string;
}

const SIZE_CLASS = {
  sm: 'max-w-sm',
  md: 'max-w-lg',
  lg: 'max-w-2xl',
} as const;

export function Modal({
  open,
  onOpenChange,
  title,
  description,
  children,
  footer,
  size = 'md',
  closeLabel = 'Close',
  className,
}: ModalProps) {
  const returnFocusRef = useRef<HTMLElement | null>(null);

  return (
    <DialogPrimitive.Root open={open} onOpenChange={onOpenChange}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-40 bg-black/40" />
        <DialogPrimitive.Content
          onOpenAutoFocus={() => {
            returnFocusRef.current = document.activeElement as HTMLElement | null;
          }}
          onCloseAutoFocus={(event) => {
            if (returnFocusRef.current?.isConnected) {
              event.preventDefault();
              returnFocusRef.current.focus();
            }
          }}
          className={cn(
            'fixed left-1/2 top-1/2 z-50 flex max-h-[calc(100dvh-2rem)] w-[calc(100%-2rem)] -translate-x-1/2 -translate-y-1/2 flex-col rounded-lg border border-border bg-surface p-5 shadow-xl focus:outline-none',
            SIZE_CLASS[size],
            className,
          )}
        >
          <div className="mb-3 flex shrink-0 items-start justify-between gap-4">
            <div>
              <DialogPrimitive.Title className="text-base font-semibold">
                {title}
              </DialogPrimitive.Title>
              {description ? (
                <DialogPrimitive.Description className="mt-1 text-sm text-muted-foreground">
                  {description}
                </DialogPrimitive.Description>
              ) : null}
            </div>
            <DialogPrimitive.Close
              aria-label={closeLabel}
              className="rounded p-1 text-muted-foreground hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </DialogPrimitive.Close>
          </div>
          <div className="min-h-0 flex-1 overflow-y-auto">{children}</div>
          {footer ? <div className="mt-5 flex shrink-0 justify-end gap-2">{footer}</div> : null}
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}

export interface DrawerProps extends Omit<ModalProps, 'size'> {
  side?: 'left' | 'right';
}

const SIDE_CLASS = {
  left: 'left-0 top-0 h-full w-full max-w-sm rounded-none border-r data-[state=closed]:slide-out-to-left data-[state=open]:slide-in-from-left',
  right:
    'right-0 top-0 h-full w-full max-w-sm rounded-none border-l data-[state=closed]:slide-out-to-right data-[state=open]:slide-in-from-right',
} as const;

export function Drawer({
  open,
  onOpenChange,
  title,
  description,
  children,
  footer,
  side = 'right',
  closeLabel = 'Close',
  className,
}: DrawerProps) {
  const returnFocusRef = useRef<HTMLElement | null>(null);

  return (
    <DialogPrimitive.Root open={open} onOpenChange={onOpenChange}>
      <DialogPrimitive.Portal>
        <DialogPrimitive.Overlay className="fixed inset-0 z-40 bg-black/40" />
        <DialogPrimitive.Content
          onOpenAutoFocus={() => {
            returnFocusRef.current = document.activeElement as HTMLElement | null;
          }}
          onCloseAutoFocus={(event) => {
            if (returnFocusRef.current?.isConnected) {
              event.preventDefault();
              returnFocusRef.current.focus();
            }
          }}
          className={cn(
            'fixed z-50 flex flex-col border-border bg-surface p-5 shadow-xl focus:outline-none',
            SIDE_CLASS[side],
            className,
          )}
        >
          <div className="mb-3 flex shrink-0 items-start justify-between gap-4">
            <div>
              <DialogPrimitive.Title className="text-base font-semibold">
                {title}
              </DialogPrimitive.Title>
              {description ? (
                <DialogPrimitive.Description className="mt-1 text-sm text-muted-foreground">
                  {description}
                </DialogPrimitive.Description>
              ) : null}
            </div>
            <DialogPrimitive.Close
              aria-label={closeLabel}
              className="rounded p-1 text-muted-foreground hover:bg-muted focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring"
            >
              <X className="h-4 w-4" aria-hidden="true" />
            </DialogPrimitive.Close>
          </div>
          <div className="min-h-0 flex-1 overflow-y-auto">{children}</div>
          {footer ? <div className="mt-5 flex shrink-0 justify-end gap-2">{footer}</div> : null}
        </DialogPrimitive.Content>
      </DialogPrimitive.Portal>
    </DialogPrimitive.Root>
  );
}
