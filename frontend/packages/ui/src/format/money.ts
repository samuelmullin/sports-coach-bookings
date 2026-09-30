const DEFAULT_MINOR_UNITS: Record<string, number> = {
  BIF: 0,
  CLP: 0,
  DJF: 0,
  GNF: 0,
  ISK: 0,
  JPY: 0,
  KMF: 0,
  KRW: 0,
  PYG: 0,
  RWF: 0,
  UGX: 0,
  VND: 0,
  VUV: 0,
  XAF: 0,
  XOF: 0,
  XPF: 0,
  BHD: 3,
  IQD: 3,
  JOD: 3,
  KWD: 3,
  LYD: 3,
  OMR: 3,
  TND: 3,
};

export function minorUnitExponent(currency: string): number {
  return DEFAULT_MINOR_UNITS[currency.toUpperCase()] ?? 2;
}

export function minorToMajor(amountMinor: number, currency: string): number {
  return amountMinor / 10 ** minorUnitExponent(currency);
}

export function majorToMinor(amountMajor: number, currency: string): number {
  return Math.round(amountMajor * 10 ** minorUnitExponent(currency));
}

export interface FormatMoneyOptions {
  locale?: string;
  currencyDisplay?: 'symbol' | 'narrowSymbol' | 'code' | 'name';
  minimumFractionDigits?: number;
}

export function formatMoney(
  amountMinor: number,
  currency: string,
  options: FormatMoneyOptions = {},
): string {
  const exponent = minorUnitExponent(currency);
  try {
    return new Intl.NumberFormat(options.locale ?? 'en-CA', {
      style: 'currency',
      currency: currency.toUpperCase(),
      currencyDisplay: options.currencyDisplay ?? 'symbol',
      minimumFractionDigits: options.minimumFractionDigits ?? exponent,
      maximumFractionDigits: exponent,
    }).format(minorToMajor(amountMinor, currency));
  } catch {
    return `${(amountMinor / 10 ** exponent).toFixed(exponent)} ${currency}`;
  }
}

export function parseMoneyToMinor(input: string, currency: string): number | null {
  const cleaned = input.replace(/[^0-9.,-]/g, '').replace(/,/g, '');
  if (cleaned === '' || cleaned === '-' || cleaned === '.') return null;
  const parsed = Number.parseFloat(cleaned);
  if (Number.isNaN(parsed)) return null;
  return majorToMinor(parsed, currency);
}
