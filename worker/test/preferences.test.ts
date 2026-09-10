import { describe, expect, it } from 'vitest';

import { ADDITION_FACTS } from '../src/additions';

/**
 * The AI used to know nothing about the person it was answering. The manual
 * engine filtered by dietary preference and the model did not, so the same
 * plate could produce a piece of grilled chicken through chat and never
 * through the builder.
 *
 * The Worker now removes ruled-out additions from the list before the model
 * sees it — it cannot choose what it was never shown, and an instruction is
 * only ever a request.
 */
describe('the catalogue the model is shown', () => {
  it('has the tags the filtering depends on', () => {
    // If the generator ever stops emitting these, every filter below silently
    // passes everything.
    expect(Object.keys(ADDITION_FACTS).length).toBeGreaterThan(20);
    expect(ADDITION_FACTS.grilled_chicken?.tags).toContain('meat');
    expect(ADDITION_FACTS.greek_yogurt?.tags).toContain('dairy');
  });

  it('leaves meat and fish out for a vegetarian', () => {
    const shown = Object.keys(ADDITION_FACTS).filter(
      (id) =>
        !(ADDITION_FACTS[id].tags.includes('meat') ||
          ADDITION_FACTS[id].tags.includes('fish')),
    );
    expect(shown).not.toContain('grilled_chicken');
    // And still leaves something worth suggesting.
    expect(shown.length).toBeGreaterThan(15);
  });

  it('leaves dairy out for someone avoiding it', () => {
    const shown = Object.keys(ADDITION_FACTS).filter(
      (id) => !ADDITION_FACTS[id].tags.includes('dairy'),
    );
    expect(shown).not.toContain('greek_yogurt');
    expect(shown.length).toBeGreaterThan(15);
  });

  it('leaves the expensive ones out on a budget', () => {
    const shown = Object.keys(ADDITION_FACTS).filter(
      (id) => ADDITION_FACTS[id].cost < 3,
    );
    expect(shown.length).toBeGreaterThan(10);
    for (const id of shown) expect(ADDITION_FACTS[id].cost).toBeLessThan(3);
  });

  it('never empties the list, whatever is ruled out at once', () => {
    // Every preference at the same time still has to leave the model
    // something to answer with, or chat dead-ends for a real person.
    const shown = Object.keys(ADDITION_FACTS).filter((id) => {
      const f = ADDITION_FACTS[id];
      return !(
        f.tags.includes('meat') ||
        f.tags.includes('fish') ||
        f.tags.includes('dairy') ||
        f.tags.includes('gluten') ||
        f.cost >= 3
      );
    });
    expect(shown.length).toBeGreaterThan(3);
  });
});
