import { describe, expect, it } from 'vitest';
import { applyAppearanceMode, normalizeAppearanceMode } from '../src/theme.js';

describe('appearance theme', () => {
  it('normalizes unknown theme values to system', () => {
    expect(normalizeAppearanceMode('dark')).toBe('dark');
    expect(normalizeAppearanceMode('sepia')).toBe('system');
  });

  it('applies manual themes and clears system mode', () => {
    const root = {
      dataset: {},
      removeAttribute(name) {
        if (name === 'data-theme') delete this.dataset.theme;
      }
    };

    expect(applyAppearanceMode(root, 'dark')).toBe('dark');
    expect(root.dataset.theme).toBe('dark');

    expect(applyAppearanceMode(root, 'system')).toBe('system');
    expect(root.dataset.theme).toBeUndefined();
  });
});
