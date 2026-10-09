export interface WebsiteLink {
  label?: string;
  url?: string;
}

export interface WebsiteImage {
  image_key?: string;
  image_url?: string;
  alt?: string;
  caption?: string;
}

export interface WebsiteContent {
  announcement?: string;
  hero?: {
    eyebrow?: string;
    title?: string;
    body?: string;
    image_key?: string;
    image_url?: string;
    primary_cta_label?: string;
    primary_cta_url?: string;
    secondary_cta_label?: string;
    secondary_cta_url?: string;
  };
  stats?: Array<{ value?: string; label?: string }>;
  story?: {
    eyebrow?: string;
    title?: string;
    body?: string;
    image_key?: string;
    image_url?: string;
  };
  features?: Array<{ title?: string; body?: string }>;
  testimonials?: Array<{ quote?: string; name?: string; detail?: string }>;
  coaches?: Array<{
    name?: string;
    title?: string;
    bio?: string;
    photo_key?: string;
    photo_url?: string;
  }>;
  gallery?: WebsiteImage[];
  sponsors?: Array<{
    name?: string;
    description?: string;
    url?: string;
    logo_key?: string;
    logo_url?: string;
  }>;
  faqs?: Array<{ question?: string; answer?: string }>;
  contact?: { email?: string; phone?: string; address?: string; hours?: string; intro?: string };
  footer?: { tagline?: string };
  seo?: { title?: string; description?: string; image_key?: string; image_url?: string };
}

export interface PublishedSite {
  enabled?: boolean;
  published_at?: string;
  content?: WebsiteContent;
}
