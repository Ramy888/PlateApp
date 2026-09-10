import { describe, expect, it } from 'vitest';

import { canonicalNonce } from '../src/integrity';

/**
 * The bug this file exists for: we issued 43-character unpadded base64url and
 * Play Integrity returned the same bytes as 44-character padded standard
 * base64. Compared as strings they never matched, so every real Play install
 * was refused. Emulators failed an earlier check and never reached this one,
 * which is why nothing caught it until a phone did.
 */
describe('canonicalNonce', () => {
  it('matches the padded form Play returns against the form we issued', () => {
    // 32 bytes: 43 characters unpadded, 44 with the single '=' restored.
    const issued = 'EhkzNYA66oafQr7bXKcLm2vTdN4pZsHjWx9yFuGtRe0';
    expect(issued).toHaveLength(43);
    expect(canonicalNonce(`${issued}=`)).toBe(issued);
    expect(canonicalNonce(issued)).toBe(issued);
  });

  it('treats standard base64 and base64url as the same bytes', () => {
    expect(canonicalNonce('ab+cd/ef==')).toBe('ab-cd_ef');
    expect(canonicalNonce('ab-cd_ef')).toBe('ab-cd_ef');
  });

  it('leaves a nonce that needs nothing done to it alone', () => {
    expect(canonicalNonce('plainToken123')).toBe('plainToken123');
    expect(canonicalNonce('')).toBe('');
  });
});
