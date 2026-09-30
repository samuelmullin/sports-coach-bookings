import { ChevronLeft, ChevronRight } from 'lucide-react';
import { Select } from './Select';
import { Button } from './Button';
import { cn } from '../lib/cn';

export interface CursorPaginationProps {
  hasPrevious?: boolean;
  hasNext?: boolean;
  onPrevious?: () => void;
  onNext?: () => void;
  loading?: boolean;
  limit?: number;
  onLimitChange?: (limit: number) => void;
  limitOptions?: number[];
  className?: string;
}

export function CursorPagination({
  hasPrevious = false,
  hasNext = false,
  onPrevious,
  onNext,
  loading,
  limit,
  onLimitChange,
  limitOptions = [10, 25, 50],
  className,
}: CursorPaginationProps) {
  return (
    <nav
      aria-label="Pagination"
      className={cn('flex items-center justify-between gap-2 px-1 py-2 text-sm', className)}
    >
      <div className="flex items-center gap-2">
        {onLimitChange && limit ? (
          <div className="flex items-center gap-2">
            <span className="text-muted-foreground">Rows</span>
            <Select
              aria-label="Rows per page"
              className="h-8 w-20"
              value={String(limit)}
              onValueChange={(value) => onLimitChange(Number(value))}
              options={limitOptions.map((option) => ({
                value: String(option),
                label: String(option),
              }))}
            />
          </div>
        ) : null}
      </div>
      <div className="flex items-center gap-2">
        <Button variant="outline" size="sm" disabled={!hasPrevious || loading} onClick={onPrevious}>
          <ChevronLeft className="h-4 w-4" aria-hidden="true" />
          Previous
        </Button>
        <Button variant="outline" size="sm" disabled={!hasNext || loading} onClick={onNext}>
          Next
          <ChevronRight className="h-4 w-4" aria-hidden="true" />
        </Button>
      </div>
    </nav>
  );
}
