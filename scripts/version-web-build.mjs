import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// Dona URLs diferents al codi de cada versió sense esborrar dades del navegador.
export async function versionWebBuild(directory) {
  const read = (name) => readFile(join(directory, name), 'utf8');
  const [index, bootstrap, main, maps] = await Promise.all([
    read('index.html'), read('flutter_bootstrap.js'),
    read('main.dart.js'), read('maps_config.js'),
  ]);
  if (!bootstrap.includes('"main.dart.js"') ||
      !index.includes('src="flutter_bootstrap.js"') ||
      !index.includes('src="maps_config.js"')) {
    throw new Error('Format de build inesperat: revisa les referències abans de publicar.');
  }
  const versioned = (name, content) => {
    const hash = createHash('sha256').update(content).digest('hex').slice(0, 16);
    const dot = name.lastIndexOf('.');
    return `${name.slice(0, dot)}.${hash}${name.slice(dot)}`;
  };
  const mainName = versioned('main.dart.js', main);
  const mapsName = versioned('maps_config.js', maps);
  const newBootstrap = bootstrap.replaceAll('"main.dart.js"', JSON.stringify(mainName));
  const bootstrapName = versioned('flutter_bootstrap.js', newBootstrap);
  const newIndex = index
    .replaceAll('src="flutter_bootstrap.js"', `src="${bootstrapName}"`)
    .replaceAll('src="maps_config.js"', `src="${mapsName}"`);

  // Conserva els originals i el service worker de retirada generat per Flutter.
  await Promise.all([
    writeFile(join(directory, mainName), main),
    writeFile(join(directory, mapsName), maps),
    writeFile(join(directory, bootstrapName), newBootstrap),
  ]);
  await writeFile(join(directory, 'index.html'), newIndex);
  return { mainName, mapsName, bootstrapName };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  await versionWebBuild(resolve(process.argv[2] ?? 'build/web'));
  console.log('Build web versionada.');
}
