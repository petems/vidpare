export type FeatureBadge = 'free' | 'open-source' | 'native' | 'privacy';
export type FeatureIconName = 'native-performance' | 'near-instant-exports' | 'local-privacy';

export interface FeatureItem {
  title: string;
  body: string;
  badge?: FeatureBadge;
  icon?: FeatureIconName;
}

export const featureItems: FeatureItem[] = [
  {
    title: 'Truly native Mac performance',
    body: 'Built directly on Apple\'s media frameworks with hardware acceleration. Trimming is fast because VidPare is a real Mac app, not a web wrapper.',
    badge: 'native',
    icon: 'native-performance'
  },
  {
    title: 'Near-instant exports',
    body: 'Most trims export in seconds, not minutes. VidPare skips re-encoding when possible, so you get lossless output with no waiting around.',
    badge: 'free',
    icon: 'near-instant-exports'
  },
  {
    title: 'Your files never leave your Mac',
    body: 'No uploads, no cloud processing, no file-size limits. Everything happens locally on your machine — your videos stay private.',
    badge: 'privacy',
    icon: 'local-privacy'
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
