const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const markReady = (): void => {
  const stagedNodes = document.querySelectorAll<HTMLElement>('[data-stage]');
  stagedNodes.forEach((node, index) => {
    node.style.setProperty('--stage-index', String(index));
  });
  document.documentElement.classList.add('js-ready');
};

if (!prefersReducedMotion && 'startViewTransition' in document) {
  // Use view transition API where supported for a cleaner first paint.
  (document as Document & { startViewTransition: (callback: () => void) => void }).startViewTransition(markReady);
} else {
  markReady();
}
