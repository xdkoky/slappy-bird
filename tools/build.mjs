// Slappy Bird - Copyright (c) 2026 xdkoky. All rights reserved. See LICENSE.
// Builds the public, scrambled copy of the game into dist/:
//   node tools/build.mjs        (run `npm install` in tools/ once first)
// The game script is wrapped in a function (so every name in it can be renamed), minified with terser,
// then lightly obfuscated. Heavy options (control-flow flattening, dead code, encoded strings) are left
// off on purpose: they slow the game loop down on phones. Saved-data keys are plain strings and are
// unchanged, so players keep their progress.
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, rmSync } from 'fs';
import { dirname, join } from 'path';
import { fileURLToPath } from 'url';
import { minify } from 'terser';
import JavaScriptObfuscator from 'javascript-obfuscator';

const root = join(dirname(fileURLToPath(import.meta.url)), '..'), out = join(root, 'dist');
const NOTICE = 'Slappy Bird - Copyright (c) 2026 xdkoky. All rights reserved. Copying, modifying, republishing or distributing this game or any part of it without written permission is not allowed.';

let html = readFileSync(join(root, 'index.html'), 'utf8');
const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];
if (scripts.length !== 2) throw new Error('expected 2 inline scripts (translations + game), found ' + scripts.length);
const [i18n, game] = scripts;

// the game: wrap, minify, obfuscate
const wrapped = '(() => {\n' + game[1] + '\n})();';
const min = await minify(wrapped, { ecma: 2020, compress: { passes: 2 }, mangle: true, format: { comments: false } });
const obf = JavaScriptObfuscator.obfuscate(min.code, {
  compact: true, target: 'browser', identifierNamesGenerator: 'hexadecimal', renameGlobals: false,
  stringArray: true, stringArrayThreshold: 0.6, stringArrayEncoding: [], stringArrayRotate: true, stringArrayShuffle: true,
  stringArrayWrappersCount: 1, stringArrayWrappersType: 'variable', stringArrayCallsTransform: false,
  transformObjectKeys: false, controlFlowFlattening: false, deadCodeInjection: false, selfDefending: false,
  debugProtection: false, disableConsoleOutput: false, numbersToExpressions: false, splitStrings: false, unicodeEscapeSequence: false,
}).getObfuscatedCode();

// the translations: just data, minified
const i18nMin = (await minify(i18n[1], { compress: false, mangle: false, format: { comments: false } })).code;

html = html.replace(game[0], () => '<script>/* ' + NOTICE + ' */\n' + obf + '</script>')
           .replace(i18n[0], () => '<script>' + i18nMin + '</script>')
           .replace(/<!--(?![\s\S]*?Copyright)[\s\S]*?-->/g, '');            // drop comments, keep the copyright one
rmSync(out, { recursive: true, force: true }); mkdirSync(out, { recursive: true });
writeFileSync(join(out, 'index.html'), html);
for (const f of ['sw.js', 'manifest.webmanifest', 'icon-180.png', 'icon-192.png', 'icon-512.png', 'LICENSE']) copyFileSync(join(root, f), join(out, f));
writeFileSync(join(out, 'README.md'), '# Slappy Bird\n\nPlay it at https://xdkoky.github.io/slappy-bird/\n\nThis repository only holds the published build of the game. ' +
  'The source code is private.\n\nCopyright (c) 2026 xdkoky. All rights reserved. See [LICENSE](LICENSE).\n');
console.log('dist/index.html', (html.length / 1024).toFixed(0) + ' KB (game script ' + (game[1].length / 1024).toFixed(0) + ' KB -> ' + (obf.length / 1024).toFixed(0) + ' KB)');
