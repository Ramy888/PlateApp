import { DurableObject } from 'cloudflare:workers';

/**
 * One instance per device.
 *
 * Spending a scan is a read-modify-write, and doing it in D1 means two requests
 * can both read "1 left" and both spend it. A Durable Object is single-threaded
 * per id, so the race cannot happen — no transactions, no optimistic retries.
 */

export interface QuotaState {
  scansUsed: number;
  previewsUsed: number;
  /** Unix seconds at which the current window opened. */
  windowStart: number;
  isPro: boolean;
  /** When the entitlement was last confirmed with RevenueCat. */
  proCheckedAt: number;
}

export interface QuotaView {
  scans: number;
  previews: number;
  resetsAt: number;
  pro: boolean;
}

export interface QuotaLimits {
  freeScansPerWeek: number;
  proScansPerMonth: number;
  proPreviewsPerMonth: number;
}

const WEEK = 7 * 24 * 60 * 60;
const MONTH = 30 * 24 * 60 * 60;

/** How long a RevenueCat answer is trusted before asking again. */
export const ENTITLEMENT_TTL_SECONDS = 60 * 60;

const EMPTY: QuotaState = {
  scansUsed: 0,
  previewsUsed: 0,
  windowStart: 0,
  isPro: false,
  proCheckedAt: 0,
};

export class QuotaCounter extends DurableObject<Env> {
  private get limits(): QuotaLimits {
    return {
      freeScansPerWeek: Number(this.env.FREE_SCANS_PER_WEEK ?? 3),
      proScansPerMonth: Number(this.env.PRO_SCANS_PER_MONTH ?? 30),
      proPreviewsPerMonth: Number(this.env.PRO_PREVIEWS_PER_MONTH ?? 10),
    };
  }

  private async load(now: number): Promise<QuotaState> {
    const stored = (await this.ctx.storage.get<QuotaState>('state')) ?? { ...EMPTY };
    // Free runs on a weekly window, Pro on a monthly one. Rolling the window
    // on read means a device that goes quiet for a month is not owed anything.
    const window = stored.isPro ? MONTH : WEEK;
    if (stored.windowStart === 0 || now - stored.windowStart >= window) {
      const rolled: QuotaState = {
        ...stored,
        scansUsed: 0,
        previewsUsed: 0,
        windowStart: now,
      };
      await this.ctx.storage.put('state', rolled);
      return rolled;
    }
    return stored;
  }

  private view(state: QuotaState): QuotaView {
    const { freeScansPerWeek, proScansPerMonth, proPreviewsPerMonth } = this.limits;
    const scanCap = state.isPro ? proScansPerMonth : freeScansPerWeek;
    const previewCap = state.isPro ? proPreviewsPerMonth : 0;
    return {
      scans: Math.max(0, scanCap - state.scansUsed),
      previews: Math.max(0, previewCap - state.previewsUsed),
      resetsAt: state.windowStart + (state.isPro ? MONTH : WEEK),
      pro: state.isPro,
    };
  }

  /** Current allowance without spending anything. */
  async peek(now: number): Promise<QuotaView> {
    return this.view(await this.load(now));
  }

  /** True when the cached entitlement is stale enough to re-check. */
  async needsEntitlementCheck(now: number): Promise<boolean> {
    const state = await this.load(now);
    return now - state.proCheckedAt >= ENTITLEMENT_TTL_SECONDS;
  }

  /**
   * Records what RevenueCat said. Changing tier restarts the window, because a
   * weekly free allowance and a monthly Pro one are not the same clock.
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
    return this.view(next);
  }

  /**
   * Spends one unit if there is one. Returns the allowance either way, so a
   * refusal can still tell the caller when it resets.
   */
  async spend(kind: 'scan' | 'preview', now: number): Promise<{ ok: boolean; quota: QuotaView }> {
    const state = await this.load(now);
    const before = this.view(state);
    const available = kind === 'scan' ? before.scans : before.previews;
    if (available <= 0) return { ok: false, quota: before };

    const next: QuotaState = {
      ...state,
      scansUsed: state.scansUsed + (kind === 'scan' ? 1 : 0),
      previewsUsed: state.previewsUsed + (kind === 'preview' ? 1 : 0),
    };
    await this.ctx.storage.put('state', next);
    return { ok: true, quota: this.view(next) };
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
