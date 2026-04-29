// serviceWorkerRegister.js
// Handles Service Worker registration, skipping WebView environments

function isProbablyWebView() {
  const ua = navigator.userAgent || "";
  return (
    /wv/.test(ua) ||
    /WebView/i.test(ua) ||
    (window.flutter_inappwebview !== undefined) ||
    (window.ReactNativeWebView !== undefined)
  );
}

window.addEventListener("load", async () => {
  if (!("serviceWorker" in navigator)) return;

  if (isProbablyWebView()) {
    console.info("Service Worker skipped inside WebView");
    return;
  }

  try {
    await navigator.serviceWorker.register("/service-worker.js");
    console.info("Service Worker registered");
  } catch (err) {
    console.warn("Service Worker registration failed:", err);
  }
});
