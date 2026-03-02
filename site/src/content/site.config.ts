export interface SiteCTA {
  downloadUrl: string;
  sourceUrl: string;
  primaryLabel: string;
  secondaryLabel: string;
}

export interface SiteConfig {
  appName: string;
  heroTitle: string;
  heroSubtitle: string;
  trustItems: string[];
  cta: SiteCTA;
}

export const siteConfig: SiteConfig = {
  appName: 'VidPare',
  heroTitle: 'Trim videos fast on macOS. No uploads. No nonsense.',
  heroSubtitle:
    'Free, open-source video trimming for Mac. Fast exports, complete privacy, zero bloat.',
  trustItems: [
    'Free',
    'Open Source (MIT)',
    'Native macOS',
    'No external dependencies'
  ],
  cta: {
    downloadUrl: 'https://github.com/petems/vidpare/releases/latest',
    sourceUrl: 'https://github.com/petems/vidpare',
    primaryLabel: 'Download for macOS',
    secondaryLabel: 'View Source on GitHub'
  }
};
