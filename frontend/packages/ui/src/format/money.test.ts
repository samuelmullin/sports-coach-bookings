import { describe, expect, it } from 'vitest';
import {
  formatMoney,
  majorToMinor,
  minorToMajor,
  minorUnitExponent,
  parseMoneyToMinor,
} from './money';

describe('money helpers', () => {
  it('knows currency exponents', () => {
    expect(minorUnitExponent('CAD')).toBe(2);
    expect(minorUnitExponent('JPY')).toBe(0);
    expect(minorUnitExponent('KWD')).toBe(3);
  });

  it('converts between minor and major units', () => {
    expect(minorToMajor(1250, 'CAD')).toBe(12.5);
    expect(majorToMinor(12.5, 'CAD')).toBe(1250);
    expect(minorToMajor(500, 'JPY')).toBe(500);
  });

  it('formats money in the given currency', () => {
    expect(formatMoney(1250, 'CAD')).toBe('$12.50');
    expect(formatMoney(0, 'CAD')).toBe('$0.00');
  });

  it('parses user input into minor units', () => {
    expect(parseMoneyToMinor('12.50', 'CAD')).toBe(1250);
    expect(parseMoneyToMinor('$1,234.56', 'CAD')).toBe(123456);
    expect(parseMoneyToMinor('', 'CAD')).toBeNull();
    expect(parseMoneyToMinor('abc', 'CAD')).toBeNull();
  });
});
