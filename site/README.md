# VidPare Product Site (`site/`)

Static marketing site for `vidpare.app`, built with Astro.

## Commands

```bash
npm ci
npm run dev
npm run build
npm run preview
```

## Quality gates

```bash
npm run check:links
npm run check:lighthouse
```

## Cloudflare Pages settings
- Framework preset: `Astro`
- Root directory: `site`
- Build command: `npm ci && npm run build`
- Output directory: `dist`
- Production domain: `vidpare.app`

See `../docs/cloudflare-pages-setup.md` for full setup steps.
