import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import worker from '../src/index';

const BASE = 'https://api.platepatch.app';
let ip = 0;

async function send(request: Request): Promise<Response> {
  const ctx = createExecutionContext();
  const response = await worker.fetch(request, env, ctx);
  await waitOnExecutionContext(ctx);
  return response;
}

async function register(): Promise<string> {
  const response = await send(
    new Request(`${BASE}/v1/device`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        'cf-connecting-ip': `10.20.${Math.floor(++ip / 250)}.${ip % 250}`,
      },
      body: JSON.stringify({ platform: 'android' }),
    }),
  );
  return ((await response.json()) as { deviceToken: string }).deviceToken;
}

function ask(token: string, names: string[]): Request {
  return new Request(`${BASE}/v1/classify`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
      'cf-connecting-ip': `10.21.${Math.floor(++ip / 250)}.${ip % 250}`,
    },
    body: JSON.stringify({ names }),
  });
}

function answers(foods: unknown) {
  return { response: JSON.stringify({ foods }) };
}

beforeEach(async () => {
  await env.DB.batch([
    env.DB.prepare('DELETE FROM food_descriptions'),
    env.DB.prepare('DELETE FROM devices'),
    env.DB.prepare('DELETE FROM rate_limits'),
  ]);
});

describe('describing a food the catalogue does not have', () => {
  it('answers in the vocabulary the engine speaks', async () => {
    const token = await register();
    vi.spyOn(env.AI, 'run').mockResolvedValue(
      answers([
        { name: 'pancakes', protein: 1, fibre: 0, fat: 1, tags: ['carb', 'gluten'], group: 'grains' },
      ]) as never,
    );

    const body = (await (await send(ask(token, ['pancakes']))).json()) as {
      foods: { name: string; protein: number; tags: string[]; group: string }[];
    };
    expect(body.foods).toHaveLength(1);
    expect(body.foods[0].name).toBe('pancakes');
    expect(body.foods[0].group).toBe('grains');
    expect(body.foods[0].tags).toEqual(['carb', 'gluten']);
  });

  it('drops a tag or group the engine has never heard of', async () => {
    // The whole point of a closed vocabulary: a model cannot introduce a new
    // concept, however confidently it invents one.
    const token = await register();
    vi.spyOn(env.AI, 'run').mockResolvedValue(
      answers([
        {
          name: 'pancakes',
          protein: 1,
          fibre: 0,
          fat: 1,
          tags: ['carb', 'keto_friendly', 'superfood'],
          group: 'brunch',
        },
      ]) as never,
    );

    const body = (await (await send(ask(token, ['pancakes']))).json()) as {
      foods: { tags: string[]; group: string }[];
    };
    expect(body.foods[0].tags).toEqual(['carb']);
    expect(body.foods[0].group).toBe('dishes');
  });

  it('clamps a score that would outweigh the whole plate', async () => {
    const token = await register();
    vi.spyOn(env.AI, 'run').mockResolvedValue(
      answers([
        { name: 'steak', protein: 99, fibre: -4, fat: 2, tags: ['meat'], group: 'protein' },
      ]) as never,
    );

    const body = (await (await send(ask(token, ['steak']))).json()) as {
      foods: { protein: number; fibre: number }[];
    };
    expect(body.foods[0].protein).toBe(3);
    expect(body.foods[0].fibre).toBe(0);
  });

  it('asks once, then remembers', async () => {
    // Same plate, same answer is a promise the app makes and a test enforces.
    // Asking a model twice would quietly break it.
    const token = await register();
    const spy = vi.spyOn(env.AI, 'run').mockResolvedValue(
      answers([
        { name: 'koshari', protein: 1, fibre: 2, fat: 1, tags: ['carb', 'plant'], group: 'dishes' },
      ]) as never,
    );

    await send(ask(token, ['koshari']));
    await send(ask(token, ['koshari']));

    expect(spy).toHaveBeenCalledTimes(1);
  });

  it('describes a whole plate in one call', async () => {
    const token = await register();
    const spy = vi.spyOn(env.AI, 'run').mockResolvedValue(
      answers([
        { name: 'pancakes', protein: 1, fibre: 0, fat: 1, tags: ['carb'], group: 'grains' },
        { name: 'shawarma', protein: 3, fibre: 1, fat: 2, tags: ['meat'], group: 'dishes' },
      ]) as never,
    );

    const body = (await (await send(ask(token, ['pancakes', 'shawarma']))).json()) as {
      foods: unknown[];
    };
    expect(body.foods).toHaveLength(2);
    expect(spy).toHaveBeenCalledTimes(1);
  });

  it('leaves the plate as it was when the model cannot help', async () => {
    const token = await register();
    vi.spyOn(env.AI, 'run').mockRejectedValue(new Error('capacity') as never);

    const response = await send(ask(token, ['pancakes']));
    expect(response.status).toBe(200);
    expect(((await response.json()) as { foods: unknown[] }).foods).toEqual([]);
  });

  it('refuses a guest', async () => {
    const response = await send(
      new Request(`${BASE}/v1/classify`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', 'cf-connecting-ip': '10.22.0.1' },
        body: JSON.stringify({ names: ['pancakes'] }),
      }),
    );
    expect(response.status).toBe(401);
  });
});
