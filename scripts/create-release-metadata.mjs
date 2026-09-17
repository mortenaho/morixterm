import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';

const tag = process.argv[2] ?? '';
const output = resolve(process.argv[3] ?? 'latest.json');
const { version } = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));

if (tag !== `v${version}`) {
  console.error(`Cannot generate metadata: ${tag || '(missing tag)'} does not match v${version}.`);
  process.exit(1);
}

const repository = process.env.GITHUB_REPOSITORY ?? 'mortenaho/morixterm';
const metadata = {
  schemaVersion: 1,
  version,
  tag,
  publishedAt: new Date().toISOString(),
  releaseUrl: `https://github.com/${repository}/releases/tag/${tag}`,
  latestReleaseApi: `https://api.github.com/repos/${repository}/releases/latest`,
};

mkdirSync(dirname(output), { recursive: true });
writeFileSync(output, `${JSON.stringify(metadata, null, 2)}\n`, 'utf8');
console.log(`Wrote release metadata for ${tag} to ${output}.`);
