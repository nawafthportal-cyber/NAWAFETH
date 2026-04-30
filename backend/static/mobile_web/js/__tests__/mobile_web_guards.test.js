const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function createStorage() {
  const store = new Map();
  return {
    getItem(key) {
      return store.has(key) ? store.get(key) : null;
    },
    setItem(key, value) {
      store.set(key, String(value));
    },
    removeItem(key) {
      store.delete(key);
    },
  };
}

function createClassList() {
  const values = new Set();
  return {
    add(...items) {
      items.forEach((item) => values.add(item));
    },
    remove(...items) {
      items.forEach((item) => values.delete(item));
    },
    contains(item) {
      return values.has(item);
    },
    toggle(item, force) {
      if (force === undefined) {
        if (values.has(item)) {
          values.delete(item);
          return false;
        }
        values.add(item);
        return true;
      }
      if (force) values.add(item);
      else values.delete(item);
      return !!force;
    },
  };
}

function createElement(tagName = 'div') {
  return {
    tagName: String(tagName || 'div').toUpperCase(),
    children: [],
    style: {},
    attributes: {},
    className: '',
    classList: createClassList(),
    textContent: '',
    appendChild(child) {
      this.children.push(child);
      return child;
    },
    querySelector(selector) {
      if (selector === '.notif-badge') {
        return this.children.find((child) => child.className === 'notif-badge hidden' || child.classList.contains('notif-badge')) || null;
      }
      return null;
    },
    setAttribute(name, value) {
      this.attributes[name] = String(value);
    },
    getAttribute(name) {
      return this.attributes[name] || null;
    },
    remove() {},
    addEventListener() {},
  };
}

function makeJwt() {
  const header = Buffer.from(JSON.stringify({ alg: 'HS256', typ: 'JWT' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({ exp: Math.floor(Date.now() / 1000) + 3600 })).toString('base64url');
  return `${header}.${payload}.signature`;
}

function loadScript(scriptPath, context) {
  const source = fs.readFileSync(scriptPath, 'utf8');
  vm.runInContext(source, context, { filename: scriptPath });
}

function createBaseContext() {
  const storage = createStorage();
  const notificationsLink = createElement('a');
  const chatsLink = createElement('a');
  const document = {
    readyState: 'loading',
    visibilityState: 'visible',
    body: { style: {}, classList: createClassList() },
    cookie: '',
    documentElement: { setAttribute() {} },
    addEventListener() {},
    getElementById() {
      return null;
    },
    hasFocus() {
      return true;
    },
    createElement,
    querySelectorAll(selector) {
      if (selector === 'a[href="/notifications/"], #btn-notifications') {
        return [notificationsLink];
      }
      if (selector === 'a[href="/chats/"], #btn-chat') {
        return [chatsLink];
      }
      return [];
    },
  };

  const window = {
    __NW_ENABLE_TEST_HOOKS__: true,
    __NW_TEST_HOOKS__: {},
    location: {
      origin: 'https://example.com',
      hostname: 'example.com',
      protocol: 'https:',
    },
    navigator: {
      userAgent: 'Mozilla/5.0',
      onLine: true,
    },
    localStorage: storage,
    sessionStorage: storage,
    setTimeout,
    clearTimeout,
    setInterval,
    clearInterval,
    addEventListener() {},
    removeEventListener() {},
    dispatchEvent() {},
    requestAnimationFrame(callback) {
      callback();
    },
    console,
    document,
    CustomEvent: function CustomEvent(name, options) {
      this.type = name;
      this.detail = options && options.detail;
    },
  };

  const context = vm.createContext({
    window,
    document,
    navigator: window.navigator,
    location: window.location,
    localStorage: storage,
    sessionStorage: storage,
    console,
    setTimeout,
    clearTimeout,
    setInterval,
    clearInterval,
    requestAnimationFrame: window.requestAnimationFrame,
    CustomEvent: window.CustomEvent,
    atob(value) {
      return Buffer.from(String(value), 'base64').toString('binary');
    },
    Blob: class Blob {
      constructor(parts, options) {
        this.parts = parts;
        this.type = options && options.type;
      }
    },
    URL,
  });

  context.window.window = window;
  context.window.globalThis = window;
  context.window.URL = URL;
  context.globalThis = context;
  context.self = window;
  return { context, window };
}

async function testServiceWorkerRegistrationSkipsWhenMissing() {
  const { context, window } = createBaseContext();
  let registerCount = 0;
  window.navigator.serviceWorker = {
    register() {
      registerCount += 1;
      return Promise.resolve();
    },
  };
  window.fetch = async () => ({ ok: false, status: 404 });
  context.fetch = window.fetch;

  loadScript(path.resolve(__dirname, '..', 'serviceWorkerRegister.js'), context);
  const result = await window.NawafethServiceWorker.registerServiceWorker(window);

  assert.equal(registerCount, 0);
  assert.equal(result.skipped, true);
  assert.equal(result.reason, 'missing');
}

async function testAnalyticsStopsRetryingAfter403() {
  const { context, window } = createBaseContext();
  const requests = [];
  window.Auth = {
    getAccessToken: () => makeJwt(),
    refreshAccessToken: async () => false,
  };
  context.Auth = window.Auth;
  window.fetch = async (url, options) => {
    requests.push({
      url,
      body: JSON.parse(options.body),
      authorization: options.headers.Authorization || '',
    });
    return { status: 403 };
  };
  context.fetch = window.fetch;

  loadScript(path.resolve(__dirname, '..', 'analytics.js'), context);

  await window.NwAnalytics.track('promo.banner_click', {
    payload: {
      visible: true,
      token: 'secret-token',
      email: 'user@example.com',
      nested: { keep: 'ok', jwt: 'secret-jwt' },
    },
  });
  await window.NwAnalytics.flush();

  assert.equal(requests.length, 1);
  assert.deepEqual(requests[0].body.events[0].payload, {
    visible: true,
    nested: { keep: 'ok' },
  });

  const blockedTrack = await window.NwAnalytics.track('promo.banner_click', { payload: { another: true } });
  const secondFlush = await window.NwAnalytics.flush();

  assert.equal(requests.length, 1);
  assert.equal(blockedTrack.skipped, true);
  assert.equal(blockedTrack.reason, 'auth_blocked');
  assert.equal(secondFlush.skipped, true);
}

async function testNavWebsocketConnectIsSingleFlight() {
  const { context, window } = createBaseContext();
  const socketInstances = [];
  window.Auth = {
    isLoggedIn: () => true,
    getAccessToken: () => makeJwt(),
    refreshAccessToken: async () => false,
    getRoleState: () => 'client',
  };
  window.ApiClient = {
    BASE: 'https://example.com',
    get: async () => ({ ok: true, data: { notifications: 1, chats: 0 } }),
  };
  context.Auth = window.Auth;
  context.ApiClient = window.ApiClient;
  window.WebSocket = class FakeWebSocket {
    constructor(url, protocols) {
      this.url = url;
      this.protocols = protocols;
      this.readyState = 0;
      socketInstances.push(this);
    }
    close() {
      this.readyState = 3;
    }
  };
  context.WebSocket = window.WebSocket;

  loadScript(path.resolve(__dirname, '..', 'nav.js'), context);
  const hooks = window.__NW_TEST_HOOKS__.nav;
  assert.equal(hooks.claimBadgeLeadership(true), true);

  await Promise.all([hooks.connectBadgeSocket(), hooks.connectBadgeSocket()]);

  assert.equal(socketInstances.length, 1);
  hooks.shutdownBadgeRealtime('navigation');
}

async function testNavUnreadBadgesDoesNotDuplicateConcurrentFetches() {
  const { context, window } = createBaseContext();
  let fetchCount = 0;
  let resolveFetch;
  const pendingFetch = new Promise((resolve) => {
    resolveFetch = resolve;
  });
  window.Auth = {
    isLoggedIn: () => true,
    getAccessToken: () => makeJwt(),
    refreshAccessToken: async () => false,
    getRoleState: () => 'client',
  };
  window.ApiClient = {
    BASE: 'https://example.com',
    get: async () => {
      fetchCount += 1;
      await pendingFetch;
      return { ok: true, data: { notifications: 2, chats: 1 } };
    },
  };
  context.Auth = window.Auth;
  context.ApiClient = window.ApiClient;
  window.WebSocket = class FakeWebSocket {
    constructor() {
      this.readyState = 1;
    }
    close() {}
  };
  context.WebSocket = window.WebSocket;

  loadScript(path.resolve(__dirname, '..', 'nav.js'), context);
  const hooks = window.__NW_TEST_HOOKS__.nav;
  assert.equal(hooks.claimBadgeLeadership(true), true);

  const first = hooks.loadUnreadBadges(false);
  const second = hooks.loadUnreadBadges(false);
  resolveFetch();
  await Promise.all([first, second]);

  assert.equal(fetchCount, 1);
}

async function main() {
  const tests = [
    ['service worker skips missing asset', testServiceWorkerRegistrationSkipsWhenMissing],
    ['analytics backs off after 403', testAnalyticsStopsRetryingAfter403],
    ['nav websocket connect is single-flight', testNavWebsocketConnectIsSingleFlight],
    ['nav unread badges avoids concurrent duplicate fetches', testNavUnreadBadgesDoesNotDuplicateConcurrentFetches],
  ];

  for (const [label, run] of tests) {
    await run();
    console.log('PASS', label);
  }
}

main().catch((error) => {
  console.error('FAIL', error && error.stack ? error.stack : error);
  process.exitCode = 1;
});
