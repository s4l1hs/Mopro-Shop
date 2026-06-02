# ImageMagick Install Baseline — `chore/make-verify-imagemagick-install`

Base `main@a67dcf69` (PR #42 merged). Closes the last red on `make-verify`.

## Reproduction
- Failing run (PR #42): https://github.com/s4l1hs/Mopro-Shop/actions/runs/26778777465 — every other step green (`property-cashback`, `internal/e2e`, lint, flutter), only `verify-image-manifest` failed:
  `audit-images: ImageMagick 'magick' not found … make: *** [Makefile:45: verify-image-manifest] Error 2`.

## §2.1 Consumer script + exact commands
`make verify-image-manifest` → `tool/audit-images.sh`. Commands used (all the **`magick`** unified binary):
- `command -v magick` (hard gate: `exit 2` if absent — line 18)
- `magick identify -format '%wx%h' "$f[0]"` (and `%k`, `%A`)
- `magick "$f[0]" -format '#%[hex:p{0,0}]' info:`

## §2.2 IM7 vs IM6 — IM7 REQUIRED
The script uses the IM7 **`magick` unified binary** (not IM6's separate `convert`/`identify`), and explicitly exits if `magick` is missing. So **ImageMagick 7 is mandatory**; IM6 does not satisfy it.

**`apt-get install imagemagick` will NOT work** on the runner: `ubuntu-latest` = Ubuntu 24.04, whose `imagemagick` package is **IM6** (6.9.x) — it ships `convert`/`identify` but **no `magick`**. The prompt's default install command would make the *install step* pass (`convert --version` exists) yet `verify-image-manifest` would still fail (`command -v magick` → exit 2). So the prompt's §3.1 default is insufficient here; §2.2/§4.2 anticipated this.

## §2.3 Runner state
PR #42's failure proves `magick` is not on the `ubuntu-latest` runner's PATH. No IM7 in Ubuntu 24.04 main repos.

## Chosen install — official IM7 static binary (AppImage), extracted once
Per non-goals (no PPA, no third-party action, no version pin beyond major, no alternative tooling, don't rewrite the IM7 script to IM6): install the official portable IM7 `magick` from `https://imagemagick.org/archive/binaries/magick`. It's an AppImage; Ubuntu 24.04 runners lack libfuse2, so extract it headless (`--appimage-extract`, built-in, no FUSE) once and symlink `AppRun` → `/usr/local/bin/magick`. Version floats within v7. Self-contained (only depends on imagemagick.org), fast (extract once, not per-call).

```
curl -fsSL https://imagemagick.org/archive/binaries/magick -o /tmp/magick.appimage
chmod +x /tmp/magick.appimage
(cd /tmp && ./magick.appimage --appimage-extract)   # no FUSE needed
sudo mv /tmp/squashfs-root /opt/imagemagick7
sudo ln -sf /opt/imagemagick7/AppRun /usr/local/bin/magick
magick --version    # fails the step loudly if not IM7 on PATH
```

Rejected: `apt install imagemagick` (IM6, no `magick`); third-party setup action (supply-chain + non-goal); PPA (non-goal); rewriting audit-images.sh to IM6 commands (changes deliberate IM7 tooling).
