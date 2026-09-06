/**
 * Server-side Pro check.
 *
 * The app keeps an `isPro` flag to decide what UI to show. This file exists
 * because that flag must never decide whether money is spent — a patched build
 * can set it to true. The only opinion that unlocks a model call is
 * RevenueCat's, asked here and cached in the device's Durable Object.
 */

const RC_BASE = 'https://api.revenuecat.com/v1';

/**
 * Asks RevenueCat whether this app user holds the Pro entitlement.
 *
 * Fails closed: any error, timeout or missing configuration returns false, so
 * an outage downgrades people to the free tier rather than handing out Pro.
 */
export async function checkEntitlement(env: Env, appUserId: string): Promise<boolean> {
  if (!env.REVENUECAT_SECRET_KEY || appUserId === '') return false;

  try {
    const response = await fetch(`${RC_BASE}/subscribers/${encodeURIComponent(appUserId)}`, {
      headers: {
        authorization: `Bearer ${env.REVENUECAT_SECRET_KEY}`,
        accept: 'application/json',
      },
      signal: AbortSignal.timeout(5_000),
    });

    // 404 means RevenueCat has never seen this user, which is a legitimate
    // "not Pro" rather than a failure worth logging loudly.
    if (response.status === 404) return false;
    if (!response.ok) {
      console.warn(JSON.stringify({ event: 'rc_check_failed', status: response.status }));
      return false;
    }

    const body = (await response.json()) as {
      subscriber?: { entitlements?: Record<string, { expires_date: string | null }> };
    };
    const entitlement = body.subscriber?.entitlements?.[env.RC_ENTITLEMENT];
    if (!entitlement) return false;

    // A null expiry is a lifetime grant. Otherwise it has to be in the future.
    if (entitlement.expires_date === null) return true;
    return Date.parse(entitlement.expires_date) > Date.now();
  } catch (error) {
    console.warn(JSON.stringify({ event: 'rc_check_error', message: String(error) }));
    return false;
  }
}
