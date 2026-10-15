import { MarketingPage } from './MarketingPage';
import { useWebsiteContent } from './useWebsiteContent';

export function GalleryPage() {
  const images = useWebsiteContent()?.gallery ?? [];
  return (
    <MarketingPage eyebrow="Gallery" title="Moments in motion.">
      <div className="columns-1 gap-4 sm:columns-2 lg:columns-3">
        {images.map((item, index) => (
          <figure key={`${item.image_url}-${index}`} className="mb-4 break-inside-avoid">
            {item.image_url ? (
              <img
                src={item.image_url}
                alt={item.alt ?? ''}
                className="w-full rounded-2xl object-cover"
                loading="lazy"
              />
            ) : null}
            {item.caption ? (
              <figcaption className="mt-2 text-sm text-muted-foreground">{item.caption}</figcaption>
            ) : null}
          </figure>
        ))}
      </div>
    </MarketingPage>
  );
}
