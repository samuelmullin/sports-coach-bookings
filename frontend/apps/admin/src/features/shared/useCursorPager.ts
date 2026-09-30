import { useCallback, useState } from 'react';

export interface CursorPager {
  cursor?: string;
  limit: number;
  pageIndex: number;
  hasPrevious: boolean;
  setLimit: (limit: number) => void;
  goNext: (next?: string) => void;
  goPrevious: () => void;
  reset: () => void;
}

export function useCursorPager(initialLimit = 25): CursorPager {
  const [limit, setLimitState] = useState(initialLimit);
  const [cursors, setCursors] = useState<(string | undefined)[]>([undefined]);
  const [pageIndex, setPageIndex] = useState(0);

  const reset = useCallback(() => {
    setCursors([undefined]);
    setPageIndex(0);
  }, []);

  const setLimit = useCallback(
    (next: number) => {
      setLimitState(next);
      reset();
    },
    [reset],
  );

  const goNext = useCallback(
    (next?: string) => {
      if (!next) return;
      setCursors((prev) => {
        const trimmed = prev.slice(0, pageIndex + 1);
        trimmed.push(next);
        return trimmed;
      });
      setPageIndex((current) => current + 1);
    },
    [pageIndex],
  );

  const goPrevious = useCallback(() => {
    setPageIndex((current) => Math.max(0, current - 1));
  }, []);

  return {
    cursor: cursors[pageIndex],
    limit,
    pageIndex,
    hasPrevious: pageIndex > 0,
    setLimit,
    goNext,
    goPrevious,
    reset,
  };
}
