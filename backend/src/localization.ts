export type Language = 'tr' | 'en';
export function languageFor(header?: string): Language {
  if (!header) return 'tr';
  const choices = header.split(',').map((entry, index) => {
    const [tag, ...parameters] = entry.trim().split(';');
    const quality = parameters.find(value => value.trim().startsWith('q='));
    const q = quality ? Number(quality.trim().slice(2)) : 1;
    return { language: tag.toLowerCase().split(/[-_]/)[0], q, index };
  }).filter(value => Number.isFinite(value.q) && value.q > 0 && value.q <= 1)
    .sort((a, b) => b.q - a.q || a.index - b.index);
  for (const value of choices) if (value.language === 'tr' || value.language === 'en') return value.language;
  return 'en';
}
const englishErrors: Record<string, string> = {
  invalid_input: 'Check the information and try again.',
  internal_error: 'The request could not be completed. Please try again.',
  unauthorized: 'Your session is no longer available. Open the app to continue.',
  session_expired: 'Your session has expired. Open the app to continue.',
  session_reused: 'This session was closed for security. Open the app to continue.',
  registration_expired: 'The account setup retry period has ended. A name or account ID cannot recover an old account.',
  registration_conflict: 'Retry account setup with the same name and preferences.',
  auth_method_removed: 'Phone sign-in is no longer supported. Update the app to create a device account. Existing sessions can still be used.',
  rate_limited: 'Too many attempts. Please try again later.',
  invalid_secret: 'The scheduler credential is invalid.',
  not_found: 'The record is unavailable or has not been shared with you.',
  forbidden: 'You do not have permission to perform this action.',
  program_disabled: 'Enable daily check-ins first.',
  idempotency_conflict: 'This request ID was already used for a different action. Please try again.',
  stale_day: 'This check-in belongs to a previous day. Refresh today’s screen.',
  stale_action: 'Please tap again to send a new check-in.',
  paused: 'Today’s check-in is paused. Resume it first.',
  invalid_invitation: 'This invitation is invalid, expired, or already used.',
  circle_limit: 'You can share your daily check-ins with up to 10 people.',
  recovery_invalid: 'The recovery key is invalid, changed, or already used. Use the new key you saved during your last recovery attempt.',
  recovery_changed: 'Recovery settings changed. Refresh and try again.',
  recovery_key_unavailable: 'This recovery key cannot be used. Generate a new key.'
};
export function errorMessage(code: string, fallback: string, language: Language): string {
  return language === 'tr' ? fallback : englishErrors[code] ?? englishErrors.internal_error;
}
export function pushBody(type: string, language: Language): string {
  if (type.startsWith('reminder')) return language === 'tr'
    ? 'Bugünkü haberinizi göndermeyi unutmayın.'
    : 'Remember to send your daily check-in.';
  return language === 'tr' ? 'Yakınınızdan yeni bir haber var.' : 'There is an update from your family.';
}
