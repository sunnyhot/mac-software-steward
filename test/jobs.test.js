import process from 'node:process';
import { describe, expect, it } from 'vitest';
import { createJob, getJob } from '../server/jobs.js';

describe('upgrade jobs', () => {
  it('continues with later commands after an earlier command fails', async () => {
    const job = createJob({
      label: 'continue after failure',
      commands: [
        {
          command: process.execPath,
          args: ['-e', 'process.exit(3)'],
          display: 'fail first',
          packageID: 'pkg:first',
          packageName: 'first'
        },
        {
          command: process.execPath,
          args: ['-e', 'console.log("second ran")'],
          display: 'run second',
          packageID: 'pkg:second',
          packageName: 'second'
        }
      ]
    });

    const finished = await waitForJob(job.id);

    expect(finished.status).toBe('failed');
    expect(finished.exitCode).toBe(3);
    expect(finished.commands).toMatchObject([
      { display: 'fail first', status: 'failed', exitCode: 3 },
      { display: 'run second', status: 'succeeded', exitCode: 0 }
    ]);
    expect(finished.commands[0].failureSummary).toContain('退出码 3');
    expect(finished.commands[0].recoverySuggestion).toContain('查看完整任务日志');
    expect(finished.commands[0].copyText).toContain('失败原因：');
    expect(finished.commands[1].failureSummary).toBe('');
    expect(finished.log.map((entry) => entry.text)).toContain('second ran');
  });
});

async function waitForJob(id) {
  const started = Date.now();
  while (Date.now() - started < 5_000) {
    const job = getJob(id);
    if (job && !['queued', 'running'].includes(job.status)) {
      return job;
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  throw new Error(`Timed out waiting for job ${id}`);
}
