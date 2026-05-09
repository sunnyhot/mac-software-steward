import os from 'node:os';
import path from 'node:path';
import { runCommand, commandExists } from './commands.js';

const SYSTEM_PROFILER = '/usr/sbin/system_profiler';
const FIND = '/usr/bin/find';

export async function scanAll(options = {}) {
  const includeGreedy = options.includeGreedy ?? true;
  const startedAt = Date.now();

  const [applications, brew, mas] = await Promise.all([
    scanApplications(),
    scanBrew({ includeGreedy }),
    scanMas()
  ]);

  const appMatches = classifyApplications(applications.items, brew, mas);
  const summary = buildScanSummary({
    applications: { ...applications, items: appMatches },
    brew,
    mas,
    elapsedMs: Date.now() - startedAt
  });

  return {
    scannedAt: new Date().toISOString(),
    includeGreedy,
    summary,
    applications: {
      ...applications,
      items: appMatches
    },
    brew,
    mas
  };
}

export async function scanApplications() {
  const profiler = await runCommand(SYSTEM_PROFILER, ['SPApplicationsDataType', '-json'], {
    timeoutMs: 120_000,
    maxOutput: 1024 * 1024 * 30
  });

  if (profiler.ok && profiler.stdout.trim()) {
    try {
      const parsed = JSON.parse(profiler.stdout);
      const items = (parsed.SPApplicationsDataType ?? [])
        .map(normalizeSystemProfilerApp)
        .filter((item) => item.path)
        .sort(sortByName);

      if (items.length > 0) {
        return {
          source: 'system_profiler',
          ok: true,
          error: '',
          items
        };
      }
    } catch (error) {
      return scanApplicationsByFind(`system_profiler JSON parse failed: ${error.message}`);
    }
  }

  return scanApplicationsByFind(profiler.stderr || 'system_profiler did not return application data');
}

async function scanApplicationsByFind(reason) {
  const roots = [
    '/Applications',
    path.join(os.homedir(), 'Applications'),
    '/System/Applications',
    '/System/Applications/Utilities'
  ];

  const existingRoots = roots.filter(Boolean);
  const result = await runCommand(FIND, [
    ...existingRoots,
    '-maxdepth',
    '3',
    '-type',
    'd',
    '-name',
    '*.app',
    '-prune',
    '-print'
  ], {
    timeoutMs: 60_000,
    maxOutput: 1024 * 1024 * 10
  });

  const items = result.stdout
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((appPath) => ({
      id: `app:${appPath}`,
      name: path.basename(appPath, '.app'),
      version: '',
      availableVersion: '',
      path: appPath,
      source: guessApplicationSource(appPath),
      obtainedFrom: '',
      lastModified: '',
      architecture: '',
      managedBy: 'manual',
      updateState: 'unknown',
      relatedPackageID: ''
    }))
    .sort(sortByName);

  return {
    source: 'find',
    ok: result.ok,
    error: result.ok ? reason : `${reason}; ${result.stderr}`.trim(),
    items
  };
}

function normalizeSystemProfilerApp(item) {
  const appPath = item.path || item.location || '';
  const name = item._name || item.name || (appPath ? path.basename(appPath, '.app') : 'Unknown App');

  return {
    id: `app:${appPath || name}`,
    name,
    version: item.version || item.short_version || '',
    availableVersion: '',
    path: appPath,
    source: guessApplicationSource(appPath, item.obtained_from),
    obtainedFrom: item.obtained_from || '',
    lastModified: item.lastModified || '',
    architecture: item.arch_kind || item.kind || '',
    signedBy: item.signed_by || '',
    managedBy: 'manual',
    updateState: 'unknown',
    relatedPackageID: ''
  };
}

function guessApplicationSource(appPath, obtainedFrom = '') {
  const source = String(obtainedFrom).toLowerCase();
  if (source.includes('app store')) return 'Mac App Store';
  if (source.includes('identified developer')) return 'Developer';
  if (source.includes('apple')) return 'Apple';
  if (appPath?.includes('/Cellar/') || appPath?.includes('/Caskroom/')) return 'Homebrew';
  if (appPath?.startsWith('/System/')) return 'Apple';
  if (appPath?.startsWith('/Applications/')) return 'Applications';
  if (appPath?.includes('/Applications/')) return 'User Applications';
  return obtainedFrom || 'Unknown';
}

export async function scanBrew(options = {}) {
  const includeGreedy = options.includeGreedy ?? true;
  const brewPath = await commandExists('brew');

  if (!brewPath) {
    return {
      available: false,
      path: '',
      version: '',
      error: 'Homebrew is not installed or not in PATH.',
      formulae: [],
      casks: [],
      outdatedCount: 0
    };
  }

  const [versionResult, prefixResult, formulaList, caskList, outdatedResult] = await Promise.all([
    runCommand(brewPath, ['--version'], { timeoutMs: 15_000 }),
    runCommand(brewPath, ['--prefix'], { timeoutMs: 15_000 }),
    runCommand(brewPath, ['list', '--formula', '--versions'], { timeoutMs: 60_000 }),
    runCommand(brewPath, ['list', '--cask', '--versions'], { timeoutMs: 60_000 }),
    runCommand(brewPath, ['outdated', '--json=v2', ...(includeGreedy ? ['--greedy'] : [])], {
      timeoutMs: 120_000,
      maxOutput: 1024 * 1024 * 20
    })
  ]);

  const installedFormulae = parseBrewVersionList(formulaList.stdout);
  const installedCasks = parseBrewVersionList(caskList.stdout);
  const outdated = parseBrewOutdated(outdatedResult.stdout);
  const formulae = mergeBrewOutdated(installedFormulae, outdated.formulae, 'formula');
  const casks = mergeBrewOutdated(installedCasks, outdated.casks, 'cask');

  return {
    available: true,
    path: brewPath,
    prefix: prefixResult.stdout.trim(),
    version: versionResult.stdout.split('\n')[0]?.trim() ?? '',
    error: [formulaList, caskList, outdatedResult]
      .filter((result) => !result.ok && result.stderr)
      .map((result) => result.stderr.trim())
      .join('\n'),
    includeGreedy,
    formulae,
    casks,
    outdatedCount: formulae.filter((item) => item.outdated).length + casks.filter((item) => item.outdated).length
  };
}

export function parseBrewVersionList(stdout = '') {
  return stdout
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [name, ...versions] = line.split(/\s+/);
      return {
        name,
        installedVersion: versions.join(', ')
      };
    });
}

export function parseBrewOutdated(stdout = '') {
  if (!stdout.trim()) return { formulae: [], casks: [] };
  try {
    const parsed = JSON.parse(stdout);
    return {
      formulae: Array.isArray(parsed.formulae) ? parsed.formulae : [],
      casks: Array.isArray(parsed.casks) ? parsed.casks : []
    };
  } catch {
    return { formulae: [], casks: [] };
  }
}

export function mergeBrewOutdated(installed, outdatedItems, kind) {
  const outdatedByName = new Map(outdatedItems.map((item) => [item.name, item]));

  return installed
    .map((item) => {
      const outdated = outdatedByName.get(item.name);
      const installedVersions = outdated?.installed_versions ?? outdated?.outdated_versions ?? [item.installedVersion].filter(Boolean);
      const currentVersion = outdated?.current_version ?? outdated?.newest_version ?? '';

      return {
        id: `brew:${kind}:${item.name}`,
        manager: 'brew',
        kind,
        name: item.name,
        installedVersion: Array.isArray(installedVersions) ? installedVersions.join(', ') : String(installedVersions || ''),
        currentVersion: Array.isArray(currentVersion) ? currentVersion.join(', ') : String(currentVersion || ''),
        pinned: Boolean(outdated?.pinned),
        autoUpdates: Boolean(outdated?.auto_updates),
        outdated: Boolean(outdated),
        upgradeable: Boolean(outdated && !outdated.pinned),
        raw: outdated ?? null
      };
    })
    .sort((a, b) => Number(b.outdated) - Number(a.outdated) || sortByName(a, b));
}

export async function scanMas() {
  const masPath = await commandExists('mas');
  if (!masPath) {
    return {
      available: false,
      path: '',
      error: 'mas CLI is not installed. Install with: brew install mas',
      apps: [],
      outdatedCount: 0
    };
  }

  const [listResult, outdatedResult] = await Promise.all([
    runCommand(masPath, ['list'], { timeoutMs: 60_000, maxOutput: 1024 * 1024 * 10 }),
    runCommand(masPath, ['outdated'], { timeoutMs: 60_000, maxOutput: 1024 * 1024 * 10 })
  ]);

  const outdated = new Map(
    outdatedResult.stdout
      .split('\n')
      .map(parseMasOutdatedLine)
      .filter(Boolean)
      .map((item) => [item.id, item])
  );

  const apps = listResult.stdout
    .split('\n')
    .map(parseMasListLine)
    .filter(Boolean)
    .map((app) => {
      const pending = outdated.get(app.appId);
      return {
        ...app,
        id: `mas:${app.appId}`,
        manager: 'mas',
        kind: 'app-store',
        currentVersion: pending?.currentVersion ?? '',
        outdated: Boolean(pending),
        upgradeable: Boolean(pending)
      };
    })
    .sort((a, b) => Number(b.outdated) - Number(a.outdated) || sortByName(a, b));

  return {
    available: true,
    path: masPath,
    error: [listResult, outdatedResult]
      .filter((result) => !result.ok && result.stderr)
      .map((result) => result.stderr.trim())
      .join('\n'),
    apps,
    outdatedCount: apps.filter((app) => app.outdated).length
  };
}

export function parseMasListLine(line = '') {
  const trimmed = line.trim();
  if (!trimmed) return null;
  const match = trimmed.match(/^(\d+)\s+(.+?)(?:\s+\((.+)\))?$/);
  if (!match) return null;
  return {
    appId: match[1],
    name: match[2].trim(),
    installedVersion: match[3]?.trim() ?? ''
  };
}

export function parseMasOutdatedLine(line = '') {
  const trimmed = line.trim();
  const bareArrowMatch = trimmed.match(/^(\d+)\s+(.+?)\s+(\S+)\s*->\s*(\S+)$/);
  if (bareArrowMatch && !trimmed.includes('(')) {
    return {
      id: bareArrowMatch[1],
      appId: bareArrowMatch[1],
      name: bareArrowMatch[2].trim(),
      installedVersion: bareArrowMatch[3].trim(),
      currentVersion: bareArrowMatch[4].trim()
    };
  }

  const parsed = parseMasListLine(line);
  if (!parsed) return null;

  const versionMatch = parsed.installedVersion.match(/^(.+?)\s*->\s*(.+)$/);
  return {
    id: parsed.appId,
    appId: parsed.appId,
    name: parsed.name,
    installedVersion: versionMatch?.[1]?.trim() ?? parsed.installedVersion,
    currentVersion: versionMatch?.[2]?.trim() ?? ''
  };
}

export function buildScanSummary({ applications, brew, mas, elapsedMs }) {
  const formulae = brew.formulae ?? [];
  const casks = brew.casks ?? [];
  const apps = mas.apps ?? [];
  const packages = [...formulae, ...casks, ...apps];

  return {
    applications: applications.items?.length ?? 0,
    brewFormulae: formulae.length,
    brewCasks: casks.length,
    masApps: apps.length,
    outdated: packages.filter((item) => item.outdated).length,
    actionable: packages.filter((item) => item.upgradeable).length,
    scanMs: elapsedMs
  };
}

export function classifyApplications(applications, brew, mas) {
  const casksByToken = new Map((brew.casks ?? []).map((cask) => [normalizeToken(cask.name), cask]));
  const masByName = new Map((mas.apps ?? []).map((app) => [normalizeToken(app.name), app]));

  return applications.map((app) => {
    const normalizedName = normalizeToken(app.name);
    const cask = casksByToken.get(normalizedName);
    const masApp = masByName.get(normalizedName);

    if (cask) {
      return {
        ...app,
        managedBy: 'brew-cask',
        updateState: cask.outdated ? 'outdated' : 'current',
        availableVersion: cask.currentVersion || '',
        relatedPackageID: cask.id || '',
        relatedPackage: cask
      };
    }

    if (masApp || app.source === 'Mac App Store') {
      return {
        ...app,
        managedBy: 'mas',
        updateState: masApp?.outdated ? 'outdated' : 'current',
        availableVersion: masApp?.currentVersion || '',
        relatedPackageID: masApp?.id || '',
        relatedPackage: masApp ?? null
      };
    }

    return app;
  });
}

export function normalizeToken(value = '') {
  return String(value)
    .toLowerCase()
    .replace(/\.app$/, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function sortByName(a, b) {
  return String(a.name || '').localeCompare(String(b.name || ''), 'zh-CN', {
    sensitivity: 'base'
  });
}
