import type { ReactNode } from 'react';
import { Link } from 'react-router-dom';

export function SiteLink({
  href,
  className,
  children,
}: {
  href?: string;
  className?: string;
  children: ReactNode;
}) {
  if (!href) return null;
  if (href.startsWith('/') && !href.startsWith('//'))
    return (
      <Link to={href} className={className}>
        {children}
      </Link>
    );
  if (/^https?:\/\//i.test(href))
    return (
      <a href={href} className={className} rel="noreferrer" target="_blank">
        {children}
      </a>
    );
  return null;
}
