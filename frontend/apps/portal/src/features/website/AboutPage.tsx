import { Button } from '@scb/ui';
import { Link } from 'react-router-dom';
import { MarketingPage } from './MarketingPage';
import { useWebsiteContent } from './useWebsiteContent';

export function AboutPage() {
  const story = useWebsiteContent()?.story;
  return (
    <MarketingPage
      eyebrow={story?.eyebrow ?? 'Our story'}
      title={story?.title ?? 'More than coaching.'}
      intro={story?.body}
    >
      {story?.image_url ? (
        <img
          src={story.image_url}
          alt=""
          className="max-h-[34rem] w-full rounded-3xl object-cover"
        />
      ) : null}
      <Button asChild className="self-start">
        <Link to="/schedule">Book a session</Link>
      </Button>
    </MarketingPage>
  );
}
