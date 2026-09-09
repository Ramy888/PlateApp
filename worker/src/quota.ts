import { DurableObject } from 'cloudflare:workers';

/**
 * One instance per device: the scan allowance, and the trial clock.
 *
 * Spending a scan is a read-modify-write, and doing it in D1 means two requests
 * can both read "1 left" and both spend it. A Durable Object is single-threaded
 * per id, so the race cannot happen — no transactions, no optimistic retries.
 *
 * The product rule this encodes: **scanning is free for seven days, then it is
 * a subscription.** Building a meal by hand never touches this file, never
 * touches the network, and is free forever.
 */

export interface QuotaState {
  scansUsed: number;
  previewsUsed: number;
  /** Unix seconds at which the current counting window opened. */
  windowStart: number;
  /** Unix seconds at which this device was first seen. Starts the trial. */
  trialStartedAt: number;
  isPro: boolean;
  /** When the entitlement was last confirmed with RevenueCat. */
  proCheckedAt: number;
}

/** What the app is told. Enough to render the right screen without guessing. */
export interface QuotaView {
  scans: number;
  previews: number;
  resetsAt: number;
  pro: boolean;
  /** True while the seven days are still running and the user is not Pro. */
  trialActive: boolean;
  /** Unix seconds the trial ends. Zero once the device is Pro. */
  trialEndsAt: number;
  /** Whole days left, rounded up. Zero when the trial is over. */
  trialDaysLeft: number;
}

const DAY = 24 * 60 * 60;
const MONTH = 30 * DAY;

/** How long scanning is free for a new device. */
export const TRIAL_DAYS = 7;

/**
 * Daily caps during the trial. Not a monetisation lever — a spend ceiling, so a
 * scripted client cannot run seven days of unlimited paid calls.
 */
const TRIAL_SCANS_PER_DAY = 5;
const TRIAL_PREVIEWS_PER_DAY = 2;

/** How long a RevenueCat answer is trusted before asking again. */
export const ENTITLEMENT_TTL_SECONDS = 60 * 60;

const EMPTY: QuotaState = {
  scansUsed: 0,
  previewsUsed: 0,
  windowStart: 0,
  trialStartedAt: 0,
  isPro: false,
  proCheckedAt: 0,
};

export class QuotaCounter extends DurableObject<Env> {
  private get proScans(): number {
    return Number(this.env.PRO_SCANS_PER_MONTH ?? 30);
  }

  private get proPreviews(): number {
    return Number(this.env.PRO_PREVIEWS_PER_MONTH ?? 10);
  }

  private get trialSeconds(): number {
    return Number(this.env.TRIAL_DAYS ?? TRIAL_DAYS) * DAY;
  }

  /**
   * Caps and window length for whatever the device currently is. Pro counts by
   * the month; a trial counts by the day, so an enthusiastic first evening does
   * not empty the whole week.
   */
  private allowance(state: QuotaState, now: number) {
    if (state.isPro) {
      return { scans: this.proScans, previews: this.proPreviews, window: MONTH };
    }
    if (this.trialActive(state, now)) {
      return { scans: TRIAL_SCANS_PER_DAY, previews: TRIAL_PREVIEWS_PER_DAY, window: DAY };
    }
    // Trial over, not subscribed: scanning stops. The rest of the app does not.
    return { scans: 0, previews: 0, window: DAY };
  }

  private trialActive(state: QuotaState, now: number): boolean {
    if (state.isPro) return false;
    if (state.trialStartedAt === 0) return true;
    return now - state.trialStartedAt < this.trialSeconds;
  }

  private async load(now: number): Promise<QuotaState> {
    const stored = (await this.ctx.storage.get<QuotaState>('state')) ?? { ...EMPTY };

    // The trial clock starts the first time a device is seen, not at install,
    // so someone who downloads and forgets does not lose their week.
    let next = stored.trialStartedAt === 0 ? { ...stored, trialStartedAt: now } : stored;

    const { window } = this.allowance(next, now);
    if (next.windowStart === 0 || now - next.windowStart >= window) {
      next = { ...next, scansUsed: 0, previewsUsed: 0, windowStart: now };
    }

    if (next !== stored) await this.ctx.storage.put('state', next);
    return next;
  }

  private view(state: QuotaState, now: number): QuotaView {
    const { scans, previews, window } = this.allowance(state, now);
    const trialActive = this.trialActive(state, now);
    const trialEndsAt = state.isPro ? 0 : state.trialStartedAt + this.trialSeconds;

    return {
      scans: Math.max(0, scans - state.scansUsed),
      previews: Math.max(0, previews - state.previewsUsed),
      resetsAt: state.windowStart + window,
      pro: state.isPro,
      trialActive,
      trialEndsAt,
      trialDaysLeft: trialActive ? Math.max(0, Math.ceil((trialEndsAt - now) / DAY)) : 0,
    };
  }

  /**
   * Carries a trial that was already running on a device over to the account
   * it has just been signed into. Only ever shortens or sets the window — an
   * account that has already had its week does not get another by signing in
   * on a new phone.
   */
  async adoptTrial(trialEndsAt: number | null, now: number): Promise<void> {
    if (!trialEndsAt) return;

    // Read raw rather than through load(), which starts the clock on first
    // touch — by then every account would look like it already had a trial.
    const stored = await this.ctx.storage.get<QuotaState>('state');
    if (stored && stored.trialStartedAt > 0) return;

    await this.ctx.storage.put('state', {
      ...(stored ?? EMPTY),
      trialStartedAt: trialEndsAt - this.trialSeconds,
    });
  }

  /** Current allowance without spending anything. */
  async peek(now: number): Promise<QuotaView> {
    return this.view(await this.load(now), now);
  }

  /** True when the cached entitlement is stale enough to re-check. */
  async needsEntitlementCheck(now: number): Promise<boolean> {
    const state = await this.load(now);
    return now - state.proCheckedAt >= ENTITLEMENT_TTL_SECONDS;
  }

  /**
   * Records what RevenueCat said. Changing tier restarts the counting window,
   * because a daily trial allowance and a monthly Pro one are not the same
   * clock. The trial start is never reset — cancelling Pro must not hand
   * someone a fresh seven days.
   */
  async setPro(isPro: boolean, now: number): Promise<QuotaView> {
    const state = await this.load(now);
    const next: QuotaState = {
      ...state,
      isPro,
      proCheckedAt: now,
      ...(isPro === state.isPro
        ? {}
        : { scansUsed: 0, previewsUsed: 0, windowStart: now }),
    };
    await this.ctx.storage.put('state', next);
    return this.view(next, now);
  }

  /**
   * Spends one unit if there is one. Returns the allowance either way, so a
   * refusal can still tell the caller why and when it changes.
   */
  async spend(kind: 'scan' | 'preview', now: number): Promise<{ ok: boolean; quota: QuotaView }> {
    const state = await this.load(now);
    const before = this.view(state, now);
    const available = kind === 'scan' ? before.scans : before.previews;
    if (available <= 0) return { ok: false, quota: before };

    const next: QuotaState = {
      ...state,
      scansUsed: state.scansUsed + (kind === 'scan' ? 1 : 0),
      previewsUsed: state.previewsUsed + (kind === 'preview' ? 1 : 0),
    };
    await this.ctx.storage.put('state', next);
    return { ok: true, quota: this.view(next, now) };
  }

  /**
   * Gives a spent unit back. Called when the model errors after the quota was
   * taken — the user should not pay for our failure.
   */
  async refund(kind: 'scan' | 'preview', now: number): Promise<void> {
    const state = await this.load(now);
    await this.ctx.storage.put('state', {
      ...state,
      scansUsed: Math.max(0, state.scansUsed - (kind === 'scan' ? 1 : 0)),
      previewsUsed: Math.max(0, state.previewsUsed - (kind === 'preview' ? 1 : 0)),
    });
  }

  /** Backs "delete my data" with something real. */
  async forget(): Promise<void> {
    await this.ctx.storage.deleteAll();
  }
}
