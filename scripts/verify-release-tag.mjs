import { readFileSync } from 'node:fs';

const tag = process.argv[2] ?? '';
const { version } = JSON.parse(readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
const expected = `v${version}`;

if (tag !== expected) {
  console.error(`Release tag ${tag || '(missing)'} does not match package version ${version}. Expected ${expected}.`);
  process.exit(1);
}

console.log(`Release tag ${tag} matches package version ${version}.`);
