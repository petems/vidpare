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
    'Free and open source video trimming for Mac, built with SwiftUI and AVFoundation for native speed and reliability.',
  trustItems: [
    'Free',
    'Open Source (MIT)',
    'Native macOS',
    'No ffmpeg dependency'
  ],
  cta: {
    downloadUrl: 'https://github.com/petems/vidpare/releases/latest',
    sourceUrl: 'https://github.com/petems/vidpare',
    primaryLabel: 'Download for macOS',
    secondaryLabel: 'View Source on GitHub'
  }
};
