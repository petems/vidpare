import { defineConfig } from 'astro/config';
import tailwind from '@astrojs/tailwind';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://vidpare.app',
  integrations: [tailwind(), sitemap()],
  vite: {
    build: {
      target: 'es2022'
    }
  }
});
