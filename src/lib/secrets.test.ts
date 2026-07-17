import { describe, expect, it } from 'vitest';
import { normalizeSecretPayload } from './secrets';

describe('normalizeSecretPayload', () => {
  it('flattens JSON secret keys to strings', () => {
    const result = normalizeSecretPayload({
      API_KEY: 'abc',
      ENABLED: true,
      COUNT: 3,
      NESTED: { a: 1 },
    });

    expect(result).toEqual({
      API_KEY: 'abc',
      ENABLED: 'true',
      COUNT: '3',
      NESTED: '{"a":1}',
    });
  });

  it('returns empty object for non-objects', () => {
    expect(normalizeSecretPayload(null)).toEqual({});
    expect(normalizeSecretPayload('x')).toEqual({});
    expect(normalizeSecretPayload([])).toEqual({});
  });
});
