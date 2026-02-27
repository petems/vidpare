export type FeatureBadge = 'free' | 'open-source' | 'native' | 'privacy';

export interface FeatureItem {
  title: string;
  body: string;
  badge?: FeatureBadge;
}

export const featureItems: FeatureItem[] = [
  {
    title: 'Native AVFoundation pipeline',
    body: 'VidPare is built in Swift/SwiftUI directly on AVFoundation and VideoToolbox, so trimming performance feels like a native Mac app because it is one.',
    badge: 'native'
  },
  {
    title: 'Passthrough trim speed',
    body: 'For common cuts, VidPare can remux without re-encoding. That means fast export times, minimal quality loss, and less waiting around.',
    badge: 'free'
  },
  {
    title: 'Local-first privacy',
    body: 'Your videos stay on your machine. No upload queue, no hidden file-size wall, and no browser tab trying to pretend it is a desktop editor.',
    badge: 'privacy'
  }
];

export const faqs: Array<{ question: string; answer: string }> = [
  {
    question: 'Is VidPare really free and open source?',
    answer: 'Yes. VidPare is MIT licensed and free to use.'
  },
  {
    question: 'Does VidPare upload my files anywhere?',
    answer: 'No. Processing is local on your Mac using AVFoundation.'
  },
  {
    question: 'Is this just a shell around ffmpeg?',
    answer: 'No. VidPare does not depend on ffmpeg. The trimming engine is native Swift + AVFoundation.'
  },
  {
    question: 'What formats are supported right now?',
    answer: 'Current focus is straightforward trimming workflows for MP4, MOV, and M4V sources.'
  },
  {
    question: 'What is on the roadmap?',
    answer: 'Near-term work includes deeper export compatibility checks, packaging improvements, and more timeline ergonomics.'
  }
];
