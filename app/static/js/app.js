/**
 * app.js — Hyperscript helpers + HTMX event glue.
 *
 * Global utilities for coordinating between HTMX server responses,
 * Hyperscript client-side logic, and wallet.js.
 */

// ────────────────────────────────────────────────────────
// HTMX global config
// ────────────────────────────────────────────────────────

// Include CSRF token in all HTMX requests
document.body.addEventListener('htmx:configRequest', (evt) => {
  // Get CSRF token from cookie
  const csrfToken = document.cookie
    .split('; ')
    .find(row => row.startsWith('csrftoken='))
    ?.split('=')[1];

  if (csrfToken) {
    evt.detail.headers['X-CSRFToken'] = csrfToken;
  }
});

// ────────────────────────────────────────────────────────
// Toast helper
// ────────────────────────────────────────────────────────

/**
 * Show a toast notification.
 * @param {string} message
 * @param {string} type — 'success' | 'error' | 'info'
 */
window.showToast = function showToast(message, type = 'info') {
  const container = document.getElementById('toast-container');
  if (!container) return;

  const id = 'toast-' + Date.now();
  const colorClasses = {
    error: 'bg-red-900/80 text-red-200 border-red-700/50',
    success: 'bg-green-900/80 text-green-200 border-green-700/50',
    info: 'bg-zinc-800/80 text-zinc-200 border-zinc-600/50',
  };

  const toast = document.createElement('div');
  toast.id = id;
  toast.className = `pointer-events-auto px-4 py-3 rounded-md text-sm shadow-lg border ${colorClasses[type] || colorClasses.info}`;
  toast.textContent = message;

  container.prepend(toast);

  // Auto-dismiss after 4s
  setTimeout(() => {
    toast.style.transition = 'opacity 300ms';
    toast.style.opacity = '0';
    setTimeout(() => toast.remove(), 300);
  }, 4000);
};

// ────────────────────────────────────────────────────────
// HTMX error handling
// ────────────────────────────────────────────────────────

document.body.addEventListener('htmx:responseError', (evt) => {
  const status = evt.detail.xhr?.status;
  if (status === 401) {
    window.showToast('Please log in to continue.', 'error');
  } else if (status === 403) {
    window.showToast('Permission denied.', 'error');
  } else if (status >= 500) {
    window.showToast('Something went wrong. Please try again.', 'error');
  }
});

// ────────────────────────────────────────────────────────
// On-chain transaction coordination
// ────────────────────────────────────────────────────────

/**
 * Listen for HTMX responses that contain data-tx-* attributes.
 * These indicate an on-chain transaction needs to be submitted.
 *
 * Pattern:
 *   1. HTMX POST → server returns partial with data-tx-action, data-tx-args
 *   2. Hyperscript `on load` on the partial calls the appropriate wallet.js fn
 *   3. On tx confirmation, dispatch txConfirmed event
 *   4. HTMX listener refreshes the relevant section
 */
document.body.addEventListener('txConfirmed', (evt) => {
  const { txHash, action } = evt.detail || {};
  console.log(`[app] Transaction confirmed: ${action} — ${txHash}`);
  window.showToast(`Transaction confirmed!`, 'success');

  // Trigger HTMX refresh on elements listening for this event
  htmx.trigger(document.body, 'refreshAfterTx', { txHash, action });
});

document.body.addEventListener('txFailed', (evt) => {
  const { error, action } = evt.detail || {};
  console.error(`[app] Transaction failed: ${action}`, error);
  window.showToast(`Transaction failed: ${error?.message || 'Unknown error'}`, 'error');
});

console.log('[app] khaaliSplit initialized');
