import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { versionWebBuild } from './version-web-build.mjs';

test('cada canvi de codi actualitza les URLs i conserva la sessió i el worker de retirada', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'caliu-web-'));
  const index = '<script src="maps_config.js"></script><script src="flutter_bootstrap.js" async></script>';
  try {
    await Promise.all(Object.entries({
      'index.html': index,
      'flutter_bootstrap.js': '_flutter.buildConfig={"builds":[{"mainJsPath":"main.dart.js"}]};_flutter.loader.load();',
      'main.dart.js': 'console.log("versió 1");',
      'maps_config.js': 'window.MAPS_API_KEY="test-only";',
      'flutter_service_worker.js': 'self.registration.unregister();',
    }).map(([name, content]) => writeFile(join(dir, name), content)));
    const first = await versionWebBuild(dir);
    const html = await readFile(join(dir, 'index.html'), 'utf8');
    assert.ok(html.includes(first.bootstrapName));
    assert.ok(html.includes(first.mapsName));
    assert.ok((await readFile(join(dir, first.bootstrapName), 'utf8')).includes(first.mainName));
    assert.equal(await readFile(join(dir, first.mainName), 'utf8'), 'console.log("versió 1");');
    assert.equal(await readFile(join(dir, first.mapsName), 'utf8'), 'window.MAPS_API_KEY="test-only";');
    assert.equal(await readFile(join(dir, 'flutter_service_worker.js'), 'utf8'), 'self.registration.unregister();');
    await writeFile(join(dir, 'index.html'), index);
    const same = await versionWebBuild(dir);
    assert.deepEqual(same, first);
    await writeFile(join(dir, 'index.html'), index);
    await writeFile(join(dir, 'main.dart.js'), 'console.log("versió 2");');
    const second = await versionWebBuild(dir);
    assert.notEqual(second.mainName, first.mainName);
    assert.notEqual(second.bootstrapName, first.bootstrapName);
    assert.equal(second.mapsName, first.mapsName);
    await writeFile(join(dir, 'index.html'), index);
    await writeFile(join(dir, 'maps_config.js'), 'window.MAPS_API_KEY="test-only-2";');
    const third = await versionWebBuild(dir);
    assert.notEqual(third.mapsName, second.mapsName);
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});

test('un format inesperat atura el desplegament abans de modificar el HTML', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'caliu-web-'));
  try {
    for (const name of ['index.html', 'flutter_bootstrap.js', 'main.dart.js', 'maps_config.js']) {
      await writeFile(join(dir, name), 'format desconegut');
    }
    await assert.rejects(versionWebBuild(dir), /Format de build inesperat/);
    assert.equal(await readFile(join(dir, 'index.html'), 'utf8'), 'format desconegut');
  } finally {
    await rm(dir, { recursive: true, force: true });
  }
});
