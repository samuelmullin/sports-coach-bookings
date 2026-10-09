import { MarketingPage } from './MarketingPage';
import { useWebsiteContent } from './useWebsiteContent';

export function FaqPage() {
  const faqs = useWebsiteContent()?.faqs ?? [];
  return (
    <MarketingPage eyebrow="FAQ" title="Questions? Answered.">
      <div className="max-w-3xl divide-y divide-border rounded-2xl border border-border bg-surface px-5">
        {faqs.map((item, index) => (
          <details key={`${item.question}-${index}`} className="group py-5">
            <summary className="cursor-pointer list-none pr-6 font-semibold">
              {item.question}
            </summary>
            <p className="mt-3 leading-7 text-muted-foreground">{item.answer}</p>
          </details>
        ))}
      </div>
    </MarketingPage>
  );
}
