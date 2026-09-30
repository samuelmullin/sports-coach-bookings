export interface PhoneCountry {
  /** ISO 3166-1 alpha-2 code. */
  iso2: string;
  name: string;
  /** International dial code, digits only (no leading `+`). */
  dialCode: string;
  /** Expected digits in the national significant number. */
  minLength: number;
  maxLength: number;
}

export interface PhoneValue {
  country: string;
  national: string;
}

/** Default region for the demo tenant (Canadian). */
export const defaultPhoneCountry = 'CA';

/** Friendly message shared with the backend validator. */
export const phoneErrorMessage = 'Enter a valid phone number for the selected country.';

export const phoneCountries: PhoneCountry[] = [
  { iso2: 'CA', name: 'Canada', dialCode: '1', minLength: 10, maxLength: 10 },
  { iso2: 'US', name: 'United States', dialCode: '1', minLength: 10, maxLength: 10 },
  { iso2: 'AU', name: 'Australia', dialCode: '61', minLength: 9, maxLength: 9 },
  { iso2: 'AT', name: 'Austria', dialCode: '43', minLength: 4, maxLength: 13 },
  { iso2: 'BE', name: 'Belgium', dialCode: '32', minLength: 8, maxLength: 9 },
  { iso2: 'BR', name: 'Brazil', dialCode: '55', minLength: 10, maxLength: 11 },
  { iso2: 'DK', name: 'Denmark', dialCode: '45', minLength: 8, maxLength: 8 },
  { iso2: 'FR', name: 'France', dialCode: '33', minLength: 9, maxLength: 9 },
  { iso2: 'DE', name: 'Germany', dialCode: '49', minLength: 4, maxLength: 11 },
  { iso2: 'HK', name: 'Hong Kong', dialCode: '852', minLength: 8, maxLength: 8 },
  { iso2: 'IN', name: 'India', dialCode: '91', minLength: 10, maxLength: 10 },
  { iso2: 'IE', name: 'Ireland', dialCode: '353', minLength: 7, maxLength: 9 },
  { iso2: 'IT', name: 'Italy', dialCode: '39', minLength: 9, maxLength: 11 },
  { iso2: 'JP', name: 'Japan', dialCode: '81', minLength: 9, maxLength: 10 },
  { iso2: 'MX', name: 'Mexico', dialCode: '52', minLength: 10, maxLength: 10 },
  { iso2: 'NL', name: 'Netherlands', dialCode: '31', minLength: 9, maxLength: 9 },
  { iso2: 'NZ', name: 'New Zealand', dialCode: '66', minLength: 8, maxLength: 10 },
  { iso2: 'NO', name: 'Norway', dialCode: '47', minLength: 8, maxLength: 8 },
  { iso2: 'PT', name: 'Portugal', dialCode: '351', minLength: 9, maxLength: 9 },
  { iso2: 'SG', name: 'Singapore', dialCode: '65', minLength: 8, maxLength: 8 },
  { iso2: 'ZA', name: 'South Africa', dialCode: '27', minLength: 9, maxLength: 9 },
  { iso2: 'ES', name: 'Spain', dialCode: '34', minLength: 9, maxLength: 9 },
  { iso2: 'SE', name: 'Sweden', dialCode: '46', minLength: 7, maxLength: 9 },
  { iso2: 'CH', name: 'Switzerland', dialCode: '41', minLength: 9, maxLength: 9 },
  { iso2: 'GB', name: 'United Kingdom', dialCode: '44', minLength: 9, maxLength: 10 },
];

/** Regional-indicator flag emoji for an ISO 3166-1 alpha-2 code. */
export function phoneFlag(iso2: string): string {
  return String.fromCodePoint(
    ...[...iso2.toUpperCase()].map((char) => 0x1f1e6 + char.charCodeAt(0) - 65),
  );
}

/** Resolves a region, falling back to the default, never returning `undefined`. */
export function findPhoneCountry(iso2: string | undefined | null): PhoneCountry {
  const match = phoneCountries.find((country) => country.iso2 === iso2?.toUpperCase());
  return match ?? phoneCountries.find((country) => country.iso2 === defaultPhoneCountry)!;
}

/** Strips every non-digit character. */
export function phoneDigits(value: string): string {
  return value.replace(/\D/g, '');
}

/** Composes an E.164 string from a country and a national number, if any. */
export function composeE164(country: string, national: string): string | undefined {
  const digits = phoneDigits(national);
  if (!digits) return undefined;
  return `+${findPhoneCountry(country).dialCode}${digits}`;
}

/** True when the national number has a plausible length for its country. */
export function isValidPhoneValue(value: PhoneValue | undefined | null): boolean {
  if (!value) return true;
  const digits = phoneDigits(value.national);
  if (!digits) return true;
  const region = findPhoneCountry(value.country);
  const significant = digits.startsWith('0') ? digits.slice(1) : digits;
  return significant.length >= region.minLength && significant.length <= region.maxLength;
}

/** Splits an E.164 string into a country and national number, if it can. */
export function splitE164(value: string | undefined | null): PhoneValue | undefined {
  if (!value) return undefined;
  const trimmed = value.trim();
  if (!trimmed.startsWith('+')) return undefined;
  const digits = phoneDigits(trimmed);
  const byLongestDialCode = [...phoneCountries].sort(
    (a, b) => b.dialCode.length - a.dialCode.length,
  );
  for (const region of byLongestDialCode) {
    if (digits.length > region.dialCode.length && digits.startsWith(region.dialCode)) {
      return { country: region.iso2, national: digits.slice(region.dialCode.length) };
    }
  }
  return undefined;
}
