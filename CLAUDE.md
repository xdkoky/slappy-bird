# Slappy Bird

Single-file HTML5 canvas game (`index.html`), played at https://xdkoky.github.io/slappy-bird/.
Copyright (c) 2026 xdkoky, all rights reserved (see LICENSE).

## Two repositories
- **xdkoky/slappy-bird-source** (private): this repo. All real work happens here.
- **xdkoky/slappy-bird** (public): GitHub Pages serves it. It holds **only the built, scrambled game**
  (`dist/`), never readable source. Its name/address must not change: players' saved progress
  (localStorage) and Home Screen apps belong to that address.

## Releasing an update
1. Bump `BUILD` in `index.html` and `VERSION` in `sw.js` (every release, or phones won't update).
2. `cd tools && npm install` (once), then `node tools/build.mjs` -> writes `dist/`.
3. Test `dist/index.html` (it has no globals; drive it by tapping), e.g. that old saves still load.
4. Commit and push the source here.
5. Publish: clone/fetch xdkoky/slappy-bird, replace its files with `dist/*`, commit
   ("Release BUILD xxxx"), push to its `main`. Pages updates within a minute.

Never copy `index.html` from this repo (or anything else readable) into the public repo.

## Notes
- Supabase SQL lives in `supabase/` and is run by hand in the Supabase SQL editor.
- Translations: `window.I18N` in `index.html` (7 languages); keys are the English strings.
