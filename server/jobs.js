import fs from 'node:fs';
import { spawn } from 'node:child_process';
import { commandExists, makeId } from './commands.js';

const jobs = new Map();
const SAFE_BREW_TOKEN = /^[A-Za-z0-9][A-Za-z0-9@._+-]*$/;

export function listJobs() {
  return [...jobs.values()]
    .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt))
    .slice(0, 25);
}

export function getJob(id) {
  return jobs.get(id) ?? null;
}

export async function createUpgradeJob(payload) {
  const commands = await commandsForPayload(payload);
  return createJob({
    label: payload.label || '升级任务',
    commands
  });
}

export function createJob({ label, commands }) {
  const job = {
    id: makeId('upgrade'),
    label,
    status: 'queued',
    createdAt: new Date().toISOString(),
    startedAt: '',
    finishedAt: '',
    exitCode: null,
    commands: commands.map((command) => ({
      ...command,
      status: 'queued',
      startedAt: '',
      finishedAt: '',
      exitCode: null
    })),
    log: []
  };

  jobs.set(job.id, job);
  void runJob(job);
  return job;
}

async function runJob(job) {
  job.status = 'running';
  job.startedAt = new Date().toISOString();
  appendLog(job, 'system', `开始：${job.label}`);

  for (const command of job.commands) {
    command.status = 'running';
    command.startedAt = new Date().toISOString();
    appendLog(job, 'command', `$ ${command.display}`);

    const result = await runStreamingCommand(command, job);
    command.exitCode = result.code;
    command.status = result.code === 0 ? 'succeeded' : 'failed';
    command.finishedAt = new Date().toISOString();

    if (result.code !== 0) {
      job.status = 'failed';
      job.exitCode = result.code;
      appendLog(job, 'system', `失败：${command.display}，退出码 ${result.code}`);
      break;
    }
  }

  if (job.status !== 'failed') {
    job.status = 'succeeded';
    job.exitCode = 0;
    appendLog(job, 'system', '完成');
  }

  job.finishedAt = new Date().toISOString();
}

function runStreamingCommand(command, job) {
  return new Promise((resolve) => {
    const child = spawn(command.command, command.args, {
      stdio: ['ignore', 'pipe', 'pipe'],
      env: process.env
    });

    child.stdout.on('data', (chunk) => appendLog(job, 'stdout', chunk.toString()));
    child.stderr.on('data', (chunk) => appendLog(job, 'stderr', chunk.toString()));
    child.on('error', (error) => {
      appendLog(job, 'stderr', error.message);
      resolve({ code: -1 });
    });
    child.on('close', (code) => resolve({ code: code ?? 0 }));
  });
}

function appendLog(job, stream, text) {
  const lines = String(text)
    .split(/\r?\n/)
    .filter((line) => line.length > 0);

  for (const line of lines) {
    job.log.push({
      at: new Date().toISOString(),
      stream,
      text: line
    });
  }

  if (job.log.length > 1_500) {
    job.log.splice(0, job.log.length - 1_500);
  }
}

async function commandsForPayload(payload) {
  if (payload.mode === 'all') return commandsForUpgradeAll(payload);
  return commandsForUpgradeOne(payload);
}

async function commandsForUpgradeOne(payload) {
  if (payload.manager === 'brew') {
    assertSafeBrewToken(payload.name);
    const brewPath = await requireCommand('brew');
    const args = ['upgrade'];
    if (payload.kind === 'cask') {
      args.push('--cask');
      if (payload.greedy) args.push('--greedy');
    } else if (payload.kind !== 'formula') {
      throw new Error('Unsupported Homebrew package kind.');
    }
    args.push(payload.name);
    return [{
      command: brewPath,
      args,
      display: ['brew', ...args].join(' ')
    }];
  }

  if (payload.manager === 'mas') {
    const appId = assertSafeMasId(payload.appId || payload.name);
    const masPath = await requireCommand('mas');
    return [{
      command: masPath,
      args: ['upgrade', appId],
      display: `mas upgrade ${appId}`
    }];
  }

  throw new Error('Unsupported upgrade manager.');
}

async function commandsForUpgradeAll(payload) {
  const commands = [];

  if (payload.brewFormulae || payload.brewCasks) {
    const brewPath = await requireCommand('brew');
    if (payload.runBrewUpdate) {
      commands.push({
        command: brewPath,
        args: ['update'],
        display: 'brew update'
      });
    }
    if (payload.brewFormulae) {
      commands.push({
        command: brewPath,
        args: ['upgrade'],
        display: 'brew upgrade'
      });
    }
    if (payload.brewCasks) {
      const args = ['upgrade', '--cask'];
      if (payload.greedy) args.push('--greedy');
      commands.push({
        command: brewPath,
        args,
        display: ['brew', ...args].join(' ')
      });
    }
  }

  if (payload.mas) {
    const masPath = await requireCommand('mas');
    commands.push({
      command: masPath,
      args: ['upgrade'],
      display: 'mas upgrade'
    });
  }

  if (commands.length === 0) {
    throw new Error('No upgrade source selected.');
  }

  return commands;
}

export async function revealInFinder(appPath) {
  if (!appPath || !appPath.endsWith('.app') || !fs.existsSync(appPath)) {
    throw new Error('Only existing .app bundles can be revealed.');
  }

  return createJob({
    label: `在 Finder 中显示 ${appPath}`,
    commands: [{
      command: '/usr/bin/open',
      args: ['-R', appPath],
      display: `open -R "${appPath}"`
    }]
  });
}

async function requireCommand(command) {
  const found = await commandExists(command);
  if (!found) throw new Error(`${command} is not installed or not in PATH.`);
  return found;
}

function assertSafeBrewToken(value) {
  if (!value || !SAFE_BREW_TOKEN.test(value)) {
    throw new Error('Invalid Homebrew token.');
  }
}

function assertSafeMasId(value) {
  const appId = String(value || '');
  if (!/^\d+$/.test(appId)) {
    throw new Error('Invalid Mac App Store app id.');
  }
  return appId;
}
