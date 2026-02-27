# Cloudflare Pages Setup for vidpare.app

## Deployment model
- Use Cloudflare Pages **Git integration** (do not use GitHub deploy action for production).
- Repo: `petems/vidpare`
- Production branch: `main`
- Root directory: `site`
- Build command: `npm ci && npm run build`
- Build output directory: `dist`

## Domain setup
1. In Cloudflare Pages project, add custom domain `vidpare.app`.
2. Add `www.vidpare.app` as an additional custom domain.
3. Keep apex as canonical domain and redirect `www` to apex.
4. Confirm SSL status is active for both hostnames.

## Redirect and headers
- Redirect rules are in `site/public/_redirects`.
- Security and caching headers are in `site/public/_headers`.

## Analytics and previews
- Enable Cloudflare Web Analytics for the Pages project.
- Keep Preview Deployments enabled for pull requests.

## Notes on GitHub Actions
- Current workflow (`.github/workflows/site-quality.yml`) is quality-only.
- It runs build, link checks, and Lighthouse threshold assertions.
- Production deploy should be handled by Cloudflare Pages Git integration.
