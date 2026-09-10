import { DurableObject } from 'cloudflare:workers';

/**
 * One instance per device: the scan allowance, and the trial clock.
 *
 * Spending a scan is a read-modify-write, and doing it in D1 means two requests
 * can both read "1 left" and both spend it. A Durable Object is single-threaded
 * per id, so the race cannot happen — no transactions, no optimistic retries.
 *
 * The product rule this encodes: **an account gets three AI generations, ever,
 * and then it is a subscription.** Building a meal by hand never touches this
 * file, never touches the network, and is free forever.
 *
 * It used to be seven free days. A clock was the wrong shape for this: it ran
 * out for people who had not used it, it gave a scripted client a week of paid
 * calls to farm, and it expired into nothing rather than into a decision.
 * Three tries end where a subscription begins.
 */

export interface QuotaState {
  scansUsed: number;
  previewsUsed: number;
  /** Unix seconds at which the current counting window opened. */
  windowStart: number;
  /** Unix seconds at which this device was first seen. Kept for old records. */
  trialStartedAt: number;
  /**
   * Free generations spent in the whole life of this account. Never reset, by
   * the window or by a change of tier — subscribing and cancelling must not
   * hand anybody a fresh three.
   */
  freeUsed: number;
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
  /** True while free tries remain and the user is not Pro. */
  trialActive: boolean;
  /** Always zero now. Kept so an older client still parses this. */
  trialEndsAt: number;
  /** Always zero now. Kept so an older client still parses this. */
  trialDaysLeft: number;
  /** Free generations left before a subscription is needed. */
  triesLeft: number;
}

const DAY = 24 * 60 * 60;
const MONTH = 30 * DAY;

/** Free AI generations per account, for the life of the account. */
export const FREE_TRIES = 3;

/** How long a RevenueCat answer is trusted before asking again. */
export const ENTITLEMENT_TTL_SECONDS = 60 * 60;

const EMPTY: QuotaState = {
  scansUsed: 0,
  previewsUsed: 0,
  windowStart: 0,
  trialStartedAt: 0,
  freeUsed: 0,
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

  private get freeTries(): number {
    const configured = Number(this.env.FREE_TRIES ?? FREE_TRIES);
    return Number.isFinite(configured) && configured >= 0 ? configured : FREE_TRIES;
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
    // One pool of tries, shared between reading a plate and drawing one,
    // because "three tries" is a promise a person can hold in their head and
    // "three of these and two of those" is not. Window zero: it never refills.
    const left = Math.max(0, this.freeTries - state.freeUsed);
    return { scans: left, previews: left, window: 0 };
  }

  private trialActive(state: QuotaState, now: number): boolean {
    if (state.isPro) return false;
    return state.freeUsed < this.freeTries;
  }

  private async load(now: number): Promise<QuotaState> {
    const stored = (await this.ctx.storage.get<QuotaState>('state')) ?? { ...EMPTY };

    // Older records predate freeUsed and would otherwise read as undefined,
    // which compares false against every number and quietly grants unlimited
    // tries.
    let next: QuotaState = stored.freeUsed === undefined
      ? { ...stored, freeUsed: 0 }
      : stored;

    const { window } = this.allowance(next, now);
    // Window zero means the free pool, which never rolls over. Only a paid
    // month refills.
    if (window > 0 && (next.windowStart === 0 || now - next.windowStart >= window)) {
      next = { ...next, scansUsed: 0, previewsUsed: 0, windowStart: now };
    }

    if (next !== stored) await this.ctx.storage.put('state', next);
    return next;
  }

  private view(state: QuotaState, now: number): QuotaView {
    const { scans, previews, window } = this.allowance(state, now);
    const triesLeft = Math.max(0, this.freeTries - state.freeUsed);

    return {
      // A subscriber counts against the month; everyone else counts against
      // the pool, which the allowance has already worked out.
      scans: state.isPro ? Math.max(0, scans - state.scansUsed) : scans,
      previews: state.isPro ? Math.max(0, previews - state.previewsUsed) : previews,
      resetsAt: window > 0 ? state.windowStart + window : 0,
      pro: state.isPro,
      trialActive: this.trialActive(state, now),
      trialEndsAt: 0,
      trialDaysLeft: 0,
      triesLeft: state.isPro ? 0 : triesLeft,
    };
  }

  /**
   * Kept as a no-op so the sign-in path does not need to know this changed.
   *
   * It used to carry a half-finished trial from a phone onto the account it
   * signed into. Free tries are counted per account from the start, so there
   * has never been anything on the device to carry.
   */
  async adoptTrial(_trialEndsAt: number | null, _now: number): Promise<void> {}

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
      // Only a free generation touches the pool. A subscriber's month is
      // counted by the two above.
      freeUsed: state.isPro ? state.freeUsed : state.freeUsed + 1,
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
      // A try we could not honour was never a try.
      freeUsed: state.isPro ? state.freeUsed : Math.max(0, state.freeUsed - 1),
    });
  }

  /** Backs "delete my data" with something real. */
  async forget(): Promise<void> {
    await this.ctx.storage.deleteAll();
  }
}
