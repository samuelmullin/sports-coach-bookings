import { useEffect } from 'react';
import { useWebsite, websiteQueryKey } from '../../api/endpoints';
import { body } from '../shared/api-utils';
import type { PublishedSite, WebsiteContent } from './types';

export function useWebsiteContent(): WebsiteContent | undefined {
  const query = useWebsite({
    query: { queryKey: websiteQueryKey(), retry: false, staleTime: 60_000 },
  });
  const site = body<PublishedSite>(query);

  useEffect(() => {
    const seo = site?.content?.seo;
    if (!seo || typeof document === 'undefined') return;
    if (seo.title) document.title = seo.title;
    setMeta('description', seo.description);
    setProperty('og:title', seo.title);
    setProperty('og:description', seo.description);
    setProperty('og:image', seo.image_url);
  }, [site]);

  return site?.content;
}

function setMeta(name: string, content?: string) {
  if (!content) return;
  let element = document.querySelector<HTMLMetaElement>(`meta[name="${name}"]`);
  if (!element) {
    element = document.createElement('meta');
    element.name = name;
    document.head.appendChild(element);
  }
  element.content = content;
}

function setProperty(property: string, content?: string) {
  if (!content) return;
  let element = document.querySelector<HTMLMetaElement>(`meta[property="${property}"]`);
  if (!element) {
    element = document.createElement('meta');
    element.setAttribute('property', property);
    document.head.appendChild(element);
  }
  element.content = content;
}
