const prefersReducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

const markReady = (): void => {
  document.documentElement.classList.add('is-ready');
};

if (!prefersReducedMotion && 'startViewTransition' in document) {
  // Use view transition API where supported for a cleaner first paint.
  (document as Document & { startViewTransition: (callback: () => void) => void }).startViewTransition(markReady);
} else {
  markReady();
}

const revealNodes = document.querySelectorAll<HTMLElement>('.reveal');
if (!prefersReducedMotion && 'IntersectionObserver' in window) {
  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (entry.isIntersecting) {
          entry.target.classList.add('in-view');
          observer.unobserve(entry.target);
        }
      });
    },
    { threshold: 0.2 }
  );

  revealNodes.forEach((node) => observer.observe(node));
} else {
  revealNodes.forEach((node) => node.classList.add('in-view'));
}
