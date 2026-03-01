/* ===================================================================
   cache.js — Client-side cache layer (Stale-While-Revalidate)
   =================================================================== */
'use strict';

const NwCache = (() => {
  const PREFIX = 'nw_cache_';
  const DEFAULT_TTL = 90; // seconds

  /**
   * Get cached data. Returns null if not found.
   * Returns { data, stale } — stale=true means data exists but expired.
   */
  function get(key) {
    try {
      const raw = localStorage.getItem(PREFIX + key);
      if (!raw) return null;
      const entry = JSON.parse(raw);
      const age = (Date.now() - entry.ts) / 1000;
      return {
        data: entry.data,
        stale: age > (entry.ttl || DEFAULT_TTL),
      };
    } catch {
      return null;
    }
  }

  /**
   * Set cache entry with optional TTL in seconds.
   */
  function set(key, data, ttl) {
    try {
      localStorage.setItem(PREFIX + key, JSON.stringify({
        data,
        ts: Date.now(),
        ttl: ttl || DEFAULT_TTL,
      }));
    } catch {
      // Storage full — silently fail
    }
  }

  /**
   * Remove a cache entry.
   */
  function remove(key) {
    try { localStorage.removeItem(PREFIX + key); } catch { /* noop */ }
  }

  /**
   * Clear all NW cache entries.
   */
  function clear() {
    try {
      const keys = [];
      for (let i = 0; i < localStorage.length; i++) {
        const k = localStorage.key(i);
        if (k && k.startsWith(PREFIX)) keys.push(k);
      }
      keys.forEach(k => localStorage.removeItem(k));
    } catch { /* noop */ }
  }

  return { get, set, remove, clear };
})();
