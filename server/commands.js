import { spawn } from 'node:child_process';
import { randomUUID } from 'node:crypto';

export function runCommand(command, args = [], options = {}) {
  const {
    timeoutMs = 30_000,
    maxOutput = 1024 * 1024 * 8,
    env = process.env
  } = options;

  return new Promise((resolve) => {
    const child = spawn(command, args, {
      env,
      stdio: ['ignore', 'pipe', 'pipe']
    });

    let stdout = '';
    let stderr = '';
    let killedByTimeout = false;

    const timer = setTimeout(() => {
      killedByTimeout = true;
      child.kill('SIGTERM');
      setTimeout(() => child.kill('SIGKILL'), 2_000).unref();
    }, timeoutMs);

    child.stdout.on('data', (chunk) => {
      stdout = appendBounded(stdout, chunk.toString(), maxOutput);
    });

    child.stderr.on('data', (chunk) => {
      stderr = appendBounded(stderr, chunk.toString(), maxOutput);
    });

    child.on('error', (error) => {
      clearTimeout(timer);
      resolve({
        ok: false,
        code: -1,
        stdout,
        stderr: stderr || error.message,
        error,
        timedOut: false
      });
    });

    child.on('close', (code) => {
      clearTimeout(timer);
      resolve({
        ok: code === 0 && !killedByTimeout,
        code,
        stdout,
        stderr,
        timedOut: killedByTimeout
      });
    });
  });
}

export async function commandExists(command) {
  const result = await runCommand('/usr/bin/env', ['which', command], {
    timeoutMs: 5_000,
    maxOutput: 8_192
  });
  return result.ok ? result.stdout.trim() : '';
}

export function makeId(prefix = 'job') {
  return `${prefix}_${randomUUID().replaceAll('-', '').slice(0, 14)}`;
}

export function appendBounded(current, addition, maxOutput) {
  const combined = current + addition;
  if (combined.length <= maxOutput) return combined;
  return combined.slice(combined.length - maxOutput);
}
