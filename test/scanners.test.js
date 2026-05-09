import { describe, expect, it } from 'vitest';
import {
  buildScanSummary,
  classifyApplications,
  mergeBrewOutdated,
  normalizeToken,
  parseBrewOutdated,
  parseBrewVersionList,
  parseMasListLine,
  parseMasOutdatedLine
} from '../server/scanners.js';

describe('scanner parsers', () => {
  it('parses brew version lists', () => {
    expect(parseBrewVersionList('node 26.0.0\nvisual-studio-code 1.100.2\n')).toEqual([
      { name: 'node', installedVersion: '26.0.0' },
      { name: 'visual-studio-code', installedVersion: '1.100.2' }
    ]);
  });

  it('merges brew outdated payloads with installed packages', () => {
    const installed = parseBrewVersionList('node 25.0.0\nwget 1.0.0\n');
    const outdated = parseBrewOutdated(JSON.stringify({
      formulae: [
        {
          name: 'node',
          installed_versions: ['25.0.0'],
          current_version: '26.0.0'
        }
      ],
      casks: []
    }));

    expect(mergeBrewOutdated(installed, outdated.formulae, 'formula')).toMatchObject([
      {
        name: 'node',
        installedVersion: '25.0.0',
        currentVersion: '26.0.0',
        outdated: true,
        upgradeable: true
      },
      {
        name: 'wget',
        outdated: false,
        upgradeable: false
      }
    ]);
  });

  it('parses mas list and outdated rows', () => {
    expect(parseMasListLine('497799835 Xcode (15.4)')).toEqual({
      appId: '497799835',
      name: 'Xcode',
      installedVersion: '15.4'
    });

    expect(parseMasOutdatedLine('497799835 Xcode (15.4 -> 15.5)')).toEqual({
      id: '497799835',
      appId: '497799835',
      name: 'Xcode',
      installedVersion: '15.4',
      currentVersion: '15.5'
    });
  });

  it('parses mas outdated rows when mas omits parentheses', () => {
    expect(parseMasOutdatedLine('497799835 Xcode 15.4 -> 15.5')).toEqual({
      id: '497799835',
      appId: '497799835',
      name: 'Xcode',
      installedVersion: '15.4',
      currentVersion: '15.5'
    });

    expect(parseMasOutdatedLine('123456789 System Toolkit Pro 2.2.1 -> 2.2.2')).toEqual({
      id: '123456789',
      appId: '123456789',
      name: 'System Toolkit Pro',
      installedVersion: '2.2.1',
      currentVersion: '2.2.2'
    });
  });

  it('normalizes app names and cask tokens for matching', () => {
    expect(normalizeToken('Visual Studio Code.app')).toBe('visual-studio-code');
    expect(normalizeToken('Google Chrome')).toBe('google-chrome');
  });

  it('counts only automatically upgradeable packages as actionable', () => {
    const summary = buildScanSummary({
      applications: { items: [{}, {}] },
      brew: {
        formulae: [
          { outdated: true, upgradeable: true },
          { outdated: true, upgradeable: false },
          { outdated: false, upgradeable: false }
        ],
        casks: [
          { outdated: true, upgradeable: true }
        ]
      },
      mas: {
        apps: [
          { outdated: true, upgradeable: false },
          { outdated: true, upgradeable: true }
        ]
      },
      elapsedMs: 42
    });

    expect(summary).toMatchObject({
      applications: 2,
      brewFormulae: 3,
      brewCasks: 1,
      masApps: 2,
      outdated: 5,
      actionable: 3,
      scanMs: 42
    });
  });

  it('adds related package versions to managed applications', () => {
    const [app] = classifyApplications([
      {
        id: 'app:/Applications/Visual Studio Code.app',
        name: 'Visual Studio Code',
        version: '1.101.2',
        path: '/Applications/Visual Studio Code.app',
        source: 'Applications',
        managedBy: 'manual',
        updateState: 'unknown'
      }
    ], {
      casks: [{
        id: 'brew:cask:visual-studio-code',
        name: 'visual-studio-code',
        currentVersion: '1.119.0',
        outdated: true
      }]
    }, { apps: [] });

    expect(app).toMatchObject({
      managedBy: 'brew-cask',
      updateState: 'outdated',
      availableVersion: '1.119.0',
      relatedPackageID: 'brew:cask:visual-studio-code'
    });
  });
});
