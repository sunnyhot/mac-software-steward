import { describe, expect, it } from 'vitest';
import {
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

  it('normalizes app names and cask tokens for matching', () => {
    expect(normalizeToken('Visual Studio Code.app')).toBe('visual-studio-code');
    expect(normalizeToken('Google Chrome')).toBe('google-chrome');
  });
});
