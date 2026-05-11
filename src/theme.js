export const appearanceModes = [
  { id: 'system', label: '跟随系统' },
  { id: 'light', label: '浅色' },
  { id: 'dark', label: '深色' }
];

export function normalizeAppearanceMode(mode) {
  return appearanceModes.some((item) => item.id === mode) ? mode : 'system';
}

export function applyAppearanceMode(root, mode) {
  const normalized = normalizeAppearanceMode(mode);
  if (normalized === 'system') {
    root.removeAttribute('data-theme');
  } else {
    root.dataset.theme = normalized;
  }
  return normalized;
}
