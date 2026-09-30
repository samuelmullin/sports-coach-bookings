import { Link } from 'react-router-dom';
import { useTranslation } from 'react-i18next';
import { AlertTriangle, Clock, X } from 'lucide-react';
import { Button } from '@scb/ui';
import { useOptionalReservation } from './ReservationProvider';

export function formatRemaining(ms: number): string {
  const totalSeconds = Math.max(0, Math.floor(ms / 1000));
  const minutes = Math.floor(totalSeconds / 60);
  const seconds = totalSeconds % 60;
  return `${minutes}:${seconds.toString().padStart(2, '0')}`;
}

/**
 * Sticky bar under the portal header showing the active guest reservation and
 * its countdown. Mounted in `PortalLayout`; renders nothing when there is no
 * reservation (or no provider, e.g. isolated component tests).
 */
export function ReservationBanner() {
  const { t } = useTranslation();
  const context = useOptionalReservation();
  if (!context) return null;

  const { reservation, status, remainingMs, shouldWarn, touch, release, clear } = context;
  if (!reservation || status === 'none' || status === 'done') return null;

  const selectAgainHref = reservation.offeringId
    ? `/offerings/${reservation.offeringId}/schedule`
    : '/schedule';

  if (status === 'expired') {
    return (
      <div
        role="status"
        data-testid="reservation-banner"
        className="border-b border-danger/40 bg-danger/10 text-sm"
      >
        <div className="mx-auto flex w-full max-w-5xl flex-wrap items-center gap-3 px-4 py-2">
          <AlertTriangle className="h-4 w-4 text-danger" aria-hidden="true" />
          <span className="flex-1">{t('reservations.expiredMessage')}</span>
          <Button asChild size="sm" variant="outline">
            <Link to={selectAgainHref}>{t('reservations.selectAgain')}</Link>
          </Button>
          <Button
            size="sm"
            variant="ghost"
            aria-label={t('reservations.dismiss')}
            onClick={() => clear()}
          >
            <X className="h-4 w-4" aria-hidden="true" />
          </Button>
        </div>
      </div>
    );
  }

  const sessionCount = reservation.sessionIds.length;

  return (
    <div
      role="status"
      data-testid="reservation-banner"
      className={`border-b text-sm ${shouldWarn ? 'border-amber-500/40 bg-amber-50' : 'border-primary/30 bg-primary/5'}`}
    >
      <div className="mx-auto flex w-full max-w-5xl flex-wrap items-center gap-3 px-4 py-2">
        <Clock
          className={`h-4 w-4 ${shouldWarn ? 'text-amber-600' : 'text-primary'}`}
          aria-hidden="true"
        />
        <span className="font-medium" data-testid="reservation-count">
          {t('reservations.holding', { count: sessionCount })}
        </span>
        <span className="text-muted-foreground">
          {t('reservations.expiresIn', { time: formatRemaining(remainingMs) })}
        </span>
        {shouldWarn ? (
          <>
            <span className="flex-1 text-amber-700">{t('reservations.idleWarning')}</span>
            <Button size="sm" onClick={() => void touch({ force: true })}>
              {t('reservations.needMoreTime')}
            </Button>
          </>
        ) : (
          <span className="flex-1" />
        )}
        <Button size="sm" variant="ghost" onClick={() => void release()}>
          {t('reservations.release')}
        </Button>
      </div>
    </div>
  );
}
