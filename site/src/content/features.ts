export type FeatureBadge = 'free' | 'open-source' | 'native' | 'privacy';

export interface FeatureItem {
  title: string;
  body: string;
  badge?: FeatureBadge;
  icon?: string;
}

export const featureItems: FeatureItem[] = [
  {
    title: 'Truly native Mac performance',
    body: 'Built directly on Apple\'s media frameworks with hardware acceleration. Trimming is fast because VidPare is a real Mac app, not a web wrapper.',
    badge: 'native',
    icon: '<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="4" width="16" height="16" rx="2"/><rect x="9" y="9" width="6" height="6"/><path d="M9 1v3"/><path d="M15 1v3"/><path d="M9 20v3"/><path d="M15 20v3"/><path d="M20 9h3"/><path d="M20 14h3"/><path d="M1 9h3"/><path d="M1 14h3"/></svg>'
  },
  {
    title: 'Near-instant exports',
    body: 'Most trims export in seconds, not minutes. VidPare skips re-encoding when possible, so you get lossless output with no waiting around.',
    badge: 'free',
    icon: '<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><polygon points="13 2 3 14 12 14 11 22 21 10 12 10 13 2"/></svg>'
  },
  {
    title: 'Your files never leave your Mac',
    body: 'No uploads, no cloud processing, no file-size limits. Everything happens locally on your machine — your videos stay private.',
    badge: 'privacy',
    icon: '<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/></svg>'
  }
];

export const faqs: Array<{ question: string; answer: string }> = [
  {
    question: 'Is VidPare really free and open source?',
    answer: 'Yes. VidPare is MIT licensed and completely free to use, modify, and distribute. You can browse the full source code on GitHub.'
  },
  {
    question: 'Does VidPare upload my files anywhere?',
    answer: 'No. All video processing happens locally on your Mac. VidPare never contacts any server, and your files never leave your machine.'
  },
  {
    question: 'Is this just a shell around ffmpeg?',
    answer: 'No. VidPare is built entirely with Swift and Apple\'s AVFoundation framework. There are no external dependencies to install or manage.'
  },
  {
    question: 'What formats are supported right now?',
    answer: 'VidPare supports MP4, MOV, and M4V files. These cover the vast majority of video files you\'ll encounter from cameras, phones, and screen recordings on macOS.'
  },
  {
    question: 'What is on the roadmap?',
    answer: 'Near-term priorities include improved export options, better packaging for easy installation, and timeline usability enhancements. Check GitHub Issues for the latest updates.'
  }
];
