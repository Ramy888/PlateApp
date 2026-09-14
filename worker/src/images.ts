import { ApiError } from './http';

/**
 * What this upload actually is, or null if it is not an image we accept.
 *
 * Decided by the first few bytes, never by the label. A label is not evidence
 * and, in this app's case, was not even correct: Flutter's
 * `http` package sends an untyped part as `application/octet-stream` rather
 * than leaving it blank, so the old `file.type || 'image/jpeg'` fallback never
 * fired — the string was there, it was just useless — and every real scan was
 * refused with 415. Eight days of them.
 *
 * Sniffing is the honest fix rather than adding octet-stream to the allow
 * list: it accepts a correct photo with a wrong label, and still refuses a PDF
 * labelled as a JPEG — which the old check waved straight through to Gemini.
 */
function typeOf(bytes: Uint8Array): string | null {
  const starts = (...signature: number[]) =>
    signature.every((byte, i) => bytes[i] === byte);

  if (starts(0xff, 0xd8, 0xff)) return 'image/jpeg';
  if (starts(0x89, 0x50, 0x4e, 0x47)) return 'image/png';
  // WEBP is RIFF with the format tag four bytes further in.
  if (starts(0x52, 0x49, 0x46, 0x46) && [0x57, 0x45, 0x42, 0x50].every((b, i) => bytes[8 + i] === b)) {
    return 'image/webp';
  }
  return null;
}

/**
 * The photo out of an already-parsed multipart form.
 *
 * Shared by scanning and by the visual preview, because they take the same
 * upload from the same phone. They used to carry two copies of this check, and
 * when the label-trusting bug was found in one the other kept it — the preview
 * had been refusing every real photo with a 415 nobody had noticed.
 *
 * The form is parsed by the caller rather than here: the preview needs the
 * addition id out of the same body.
 */
export async function imageFrom(
  form: FormData,
  maxBytes: number,
): Promise<{ bytes: Uint8Array; mimeType: string }> {
  const file = form.get('image');
  if (!(file instanceof File)) {
    throw new ApiError(400, 'missing_image', 'No photo was attached.');
  }
  if (file.size === 0) {
    throw new ApiError(400, 'empty_image', 'That photo was empty.');
  }
  if (file.size > maxBytes) {
    throw new ApiError(413, 'image_too_large', 'That photo is too large to send.');
  }

  const bytes = new Uint8Array(await file.arrayBuffer());
  const mimeType = typeOf(bytes);
  if (mimeType === null) {
    throw new ApiError(415, 'unsupported_type', 'Send a JPEG or PNG.');
  }
  return { bytes, mimeType };
}
