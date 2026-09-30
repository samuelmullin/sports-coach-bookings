import { describe, expect, it } from 'vitest';
import { composeE164, isValidPhoneValue, phoneDigits, phoneFlag, splitE164 } from './phone';

describe('phone helpers', () => {
  it('composes E.164 from a country and national number', () => {
    expect(composeE164('CA', '9025550111')).toBe('+19025550111');
    expect(composeE164('US', '415-555-0123')).toBe('+14155550123');
    expect(composeE164('GB', '7911123456')).toBe('+447911123456');
    expect(composeE164('AU', '412345678')).toBe('+61412345678');
    expect(composeE164('CA', '')).toBeUndefined();
  });

  it('splits E.164 back into a country and national number', () => {
    expect(splitE164('+19025550111')).toEqual({ country: 'CA', national: '9025550111' });
    expect(splitE164('+61412345678')).toEqual({ country: 'AU', national: '412345678' });
    expect(splitE164('+353861234567')).toEqual({ country: 'IE', national: '861234567' });
    expect(splitE164('not-a-phone')).toBeUndefined();
    expect(splitE164(undefined)).toBeUndefined();
  });

  it('validates plausible national lengths', () => {
    expect(isValidPhoneValue({ country: 'CA', national: '9025550111' })).toBe(true);
    expect(isValidPhoneValue({ country: 'CA', national: '123' })).toBe(false);
    expect(isValidPhoneValue({ country: 'CA', national: '' })).toBe(true);
    expect(isValidPhoneValue(undefined)).toBe(true);
  });

  it('renders a regional-indicator flag emoji', () => {
    expect(phoneFlag('CA')).toBe('\u{1F1E8}\u{1F1E6}');
  });

  it('strips non-digit characters', () => {
    expect(phoneDigits('+1 (902) 555-0111')).toBe('19025550111');
  });
});
