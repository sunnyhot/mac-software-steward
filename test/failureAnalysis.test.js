import { describe, expect, it } from 'vitest';
import { analyzeFailure } from '../src/failureAnalysis.js';

describe('failure analysis', () => {
  it('turns unclear command output into copyable reason and next steps', () => {
    const analysis = analyzeFailure({
      command: 'brew upgrade --cask --greedy folo',
      code: 1,
      output: [
        '[stdout] ==> Upgrading 1 outdated package:',
        '[stdout] folo 1.2.6 -> 1.7.0',
        '[stdout] ==> Upgrading folo'
      ].join('\n')
    });

    expect(analysis.summary).toContain('退出码 1');
    expect(analysis.summary).toContain('没有捕获到明确错误行');
    expect(analysis.suggestion).toContain('查看完整任务日志');
    expect(analysis.suggestion).toContain('brew upgrade --cask --greedy folo');
    expect(analysis.copyText).toContain('失败原因：');
    expect(analysis.copyText).toContain('解决方案：');
    expect(analysis.copyText).toContain('命令：brew upgrade --cask --greedy folo');
  });

  it('does not describe skipped work as previous-step failure', () => {
    const analysis = analyzeFailure({
      command: 'brew upgrade --cask --greedy google-chrome@canary',
      code: null,
      output: '',
      skipped: true
    });

    expect(analysis.summary).toContain('未开始执行');
    expect(analysis.copyText).not.toContain('前一步');
  });
});
