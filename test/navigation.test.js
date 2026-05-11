import { describe, expect, it } from 'vitest';
import { tabs } from '../src/navigation.js';

describe('navigation', () => {
  it('keeps primary tabs focused on tasks, sources, settings, and logs', () => {
    expect(tabs.map((tab) => tab.label)).toEqual([
      '可升级',
      '本机应用',
      '管理来源',
      '设置',
      '任务日志'
    ]);
  });
});
