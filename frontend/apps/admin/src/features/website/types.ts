export interface WebsiteContent {
  announcement?: string;
  hero?: Record<string, string>;
  stats?: Array<{ value?: string; label?: string }>;
  story?: Record<string, string>;
  features?: Array<{ title?: string; body?: string }>;
  testimonials?: Array<{ quote?: string; name?: string; detail?: string }>;
  coaches?: Array<{ name?: string; title?: string; bio?: string; photo_key?: string }>;
  gallery?: Array<{ image_key?: string; alt?: string; caption?: string }>;
  sponsors?: Array<{ name?: string; description?: string; url?: string; logo_key?: string }>;
  faqs?: Array<{ question?: string; answer?: string }>;
  contact?: Record<string, string>;
  footer?: Record<string, string>;
  seo?: Record<string, string>;
}
