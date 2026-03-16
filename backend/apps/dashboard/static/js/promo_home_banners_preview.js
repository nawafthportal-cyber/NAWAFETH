(() => {
  function clampScale(rawValue, fallback, minimum, maximum) {
    const parsed = Number.parseInt(rawValue, 10);
    if (!Number.isFinite(parsed)) return fallback;
    return Math.max(minimum, Math.min(parsed, maximum));
  }

  function normalizeMediaType(value) {
    return String(value || '').toLowerCase() === 'video' ? 'video' : 'image';
  }

  function classifyAspectRatio(width, height) {
    const safeWidth = Number(width) || 0;
    const safeHeight = Number(height) || 0;
    if (!(safeWidth > 0 && safeHeight > 0)) return 'unknown';
    const ratio = safeWidth / safeHeight;
    if (ratio <= 0.8) return 'portrait';
    if (ratio >= 2.05) return 'ultrawide';
    if (ratio >= 1.15) return 'landscape';
    return 'square';
  }

  function describePreset(kind, mediaType) {
    if (mediaType === 'video') {
      if (kind === 'portrait') return 'فيديو طولي';
      if (kind === 'ultrawide') return 'فيديو عريض جدًا';
      if (kind === 'landscape') return 'فيديو أفقي';
      if (kind === 'square') return 'فيديو شبه مربّع';
      return 'فيديو';
    }
    if (kind === 'portrait') return 'صورة طولية';
    if (kind === 'ultrawide') return 'صورة عريضة جدًا';
    if (kind === 'landscape') return 'صورة أفقية';
    if (kind === 'square') return 'صورة مربّعة';
    return 'وسائط عامة';
  }

  function recommendedScales(mediaType, aspectKind) {
    if (mediaType === 'video') {
      if (aspectKind === 'portrait') return { mobile: 122, tablet: 112, desktop: 96 };
      if (aspectKind === 'square') return { mobile: 110, tablet: 102, desktop: 96 };
      if (aspectKind === 'ultrawide') return { mobile: 86, tablet: 92, desktop: 100 };
      if (aspectKind === 'landscape') return { mobile: 94, tablet: 98, desktop: 104 };
      return { mobile: 96, tablet: 100, desktop: 104 };
    }

    if (aspectKind === 'portrait') return { mobile: 126, tablet: 114, desktop: 98 };
    if (aspectKind === 'square') return { mobile: 110, tablet: 102, desktop: 96 };
    if (aspectKind === 'ultrawide') return { mobile: 84, tablet: 92, desktop: 102 };
    if (aspectKind === 'landscape') return { mobile: 96, tablet: 102, desktop: 108 };
    return { mobile: 100, tablet: 100, desktop: 100 };
  }

  function presetCatalog() {
    return {
      'portrait-strong': {
        label: 'طولي قوي',
        description: 'مناسب للصور الطولية أو الإعلانات التي تحتاج بروزًا أعلى داخل الهيرو.',
        scales: { mobile: 128, tablet: 116, desktop: 100 },
      },
      'landscape-balanced': {
        label: 'أفقي متوازن',
        description: 'قالب عام متزن للصور الأفقية ويحافظ على حضور جيد عبر مختلف المقاسات.',
        scales: { mobile: 96, tablet: 102, desktop: 108 },
      },
      'video-light': {
        label: 'فيديو خفيف',
        description: 'يخفف سيطرة الفيديو على المساحة ويترك متنفسًا أوضح لعناصر الواجهة فوقه.',
        scales: { mobile: 88, tablet: 94, desktop: 100 },
      },
    };
  }

  function toggleHidden(element, hidden) {
    if (!element) return;
    element.classList.toggle('hidden', hidden);
  }

  function initBannerEditor(editor) {
    const preview = editor.querySelector('[data-banner-preview]');
    if (!preview) return;

    const titleInput = editor.querySelector('[name="title"]');
    const mediaTypeInput = editor.querySelector('[name="media_type"]');
    const fileInput = editor.querySelector('[name="media_file"]');
    const mobileScaleInput = editor.querySelector('[name="mobile_scale"]');
    const tabletScaleInput = editor.querySelector('[name="tablet_scale"]');
    const desktopScaleInput = editor.querySelector('[name="desktop_scale"]');
    const titleNode = preview.querySelector('[data-preview-title]');
    const imageEl = preview.querySelector('[data-preview-image]');
    const videoEl = preview.querySelector('[data-preview-video]');
    const placeholderEl = preview.querySelector('[data-preview-placeholder]');
    const mobileScaleMetric = preview.querySelector('[data-preview-mobile-scale-label]');
    const tabletScaleMetric = preview.querySelector('[data-preview-tablet-scale-label]');
    const desktopScaleMetric = preview.querySelector('[data-preview-desktop-scale-label]');
    const mobileScaleOutputs = editor.querySelectorAll('[data-range-output="mobile"]');
    const tabletScaleOutputs = editor.querySelectorAll('[data-range-output="tablet"]');
    const desktopScaleOutputs = editor.querySelectorAll('[data-range-output="desktop"]');
    const deviceButtons = preview.querySelectorAll('[data-preview-device-btn]');
    const smartDefaultsSummary = editor.querySelector('[data-smart-defaults-summary]');
    const smartDefaultsApplyButton = editor.querySelector('[data-smart-defaults-apply]');
    const smartPresetSummary = editor.querySelector('[data-smart-preset-summary]');
    const presetButtons = editor.querySelectorAll('[data-smart-preset]');
    const presets = presetCatalog();
    const initialSrc = preview.dataset.previewSrc || '';
    const initialKind = normalizeMediaType(preview.dataset.previewKind || (mediaTypeInput && mediaTypeInput.value));
    const mobileMin = Number.parseInt(mobileScaleInput?.min || '40', 10);
    const mobileMax = Number.parseInt(mobileScaleInput?.max || '140', 10);
    const tabletMin = Number.parseInt(tabletScaleInput?.min || '40', 10);
    const tabletMax = Number.parseInt(tabletScaleInput?.max || '150', 10);
    const desktopMin = Number.parseInt(desktopScaleInput?.min || '40', 10);
    const desktopMax = Number.parseInt(desktopScaleInput?.max || '160', 10);
    const defaultMobile = Number.parseInt(mobileScaleInput?.value || '100', 10) || 100;
    const defaultTablet = Number.parseInt(tabletScaleInput?.value || '100', 10) || 100;
    const defaultDesktop = Number.parseInt(desktopScaleInput?.value || '100', 10) || 100;
    const manualScaleState = {
      mobile: false,
      tablet: false,
      desktop: false,
    };
    let pendingMediaMeta = {
      mediaType: normalizeMediaType(mediaTypeInput?.value),
      aspectKind: 'unknown',
      width: 0,
      height: 0,
      source: initialSrc ? 'current' : 'empty',
    };
    let activePresetKey = '';
    let objectUrl = '';

    function releaseObjectUrl() {
      if (!objectUrl) return;
      URL.revokeObjectURL(objectUrl);
      objectUrl = '';
    }

    function syncTitle() {
      if (!titleNode) return;
      const value = String(titleInput?.value || '').trim();
      titleNode.textContent = value || 'عنوان الإعلان';
    }

    function syncScale(input, cssVarName, outputs, metricEl, minimum, maximum, fallback) {
      const value = clampScale(input?.value, fallback, minimum, maximum);
      preview.style.setProperty(cssVarName, String(value / 100));
      outputs.forEach((node) => {
        node.textContent = `${value}%`;
      });
      if (metricEl) metricEl.textContent = `${value}%`;
    }

    function setScaleValue(input, value) {
      if (!input) return;
      input.value = String(value);
      input.dispatchEvent(new Event('input', { bubbles: true }));
    }

    function setPresetButtonState(activeKey) {
      activePresetKey = activeKey || '';
      presetButtons.forEach((button) => {
        const isActive = button.dataset.smartPreset === activePresetKey;
        button.classList.toggle('bg-fuchsia-600', isActive);
        button.classList.toggle('text-white', isActive);
        button.classList.toggle('ring-fuchsia-600', isActive);
        button.classList.toggle('shadow-md', isActive);
        button.classList.toggle('bg-white', !isActive);
        button.classList.toggle('text-slate-700', !isActive);
        button.classList.toggle('ring-slate-200', !isActive);
      });
    }

    function markManualScales() {
      manualScaleState.mobile = true;
      manualScaleState.tablet = true;
      manualScaleState.desktop = true;
    }

    function buildSummaryText() {
      const meta = pendingMediaMeta;
      const label = describePreset(meta.aspectKind, meta.mediaType);
      if (meta.aspectKind === 'unknown') {
        if (meta.source === 'empty') {
          return 'اختر ملفًا أو غيّر نوع الوسائط ليقترح النظام قياسات مناسبة تلقائيًا.';
        }
        return `اقتراح افتراضي ل${meta.mediaType === 'video' ? 'لفيديو' : 'صورة'} بدون أبعاد مكتشفة بعد.`;
      }
      return `تم التعرف على ${label}${meta.width && meta.height ? ` بنسبة ${meta.width}×${meta.height}` : ''} واقتراح قياسات مناسبة لظهوره داخل الهيرو.`;
    }

    function applySmartDefaults(force) {
      const preset = recommendedScales(pendingMediaMeta.mediaType, pendingMediaMeta.aspectKind);
      let didApply = false;
      if (force || !manualScaleState.mobile) {
        setScaleValue(mobileScaleInput, preset.mobile);
        didApply = true;
      }
      if (force || !manualScaleState.tablet) {
        setScaleValue(tabletScaleInput, preset.tablet);
        didApply = true;
      }
      if (force || !manualScaleState.desktop) {
        setScaleValue(desktopScaleInput, preset.desktop);
        didApply = true;
      }
      if (force) {
        manualScaleState.mobile = false;
        manualScaleState.tablet = false;
        manualScaleState.desktop = false;
      }
      if (force || didApply) {
        setPresetButtonState('');
      }
      if (smartDefaultsSummary) {
        smartDefaultsSummary.textContent = `${buildSummaryText()} القيم المقترحة: جوال ${preset.mobile}%، تابلت ${preset.tablet}%، ديسكتوب ${preset.desktop}%.`;
      }
      if (smartPresetSummary && (force || didApply)) {
        smartPresetSummary.textContent = 'اختر قالبًا جاهزًا لتعبئة القياسات مباشرة، ثم عدل يدويًا إذا احتجت.';
      }
    }

    function rememberMediaMeta({ mediaType, width, height, source }) {
      pendingMediaMeta = {
        mediaType: normalizeMediaType(mediaType || mediaTypeInput?.value),
        aspectKind: classifyAspectRatio(width, height),
        width: Math.round(Number(width) || 0),
        height: Math.round(Number(height) || 0),
        source: source || 'auto',
      };
      applySmartDefaults(false);
    }

    function applyFallbackSmartDefaults(source) {
      rememberMediaMeta({
        mediaType: normalizeMediaType(mediaTypeInput?.value),
        width: 0,
        height: 0,
        source,
      });
    }

    function applyPreset(presetKey) {
      const preset = presets[presetKey];
      if (!preset) return;
      setScaleValue(mobileScaleInput, preset.scales.mobile);
      setScaleValue(tabletScaleInput, preset.scales.tablet);
      setScaleValue(desktopScaleInput, preset.scales.desktop);
      markManualScales();
      setPresetButtonState(presetKey);
      if (smartPresetSummary) {
        smartPresetSummary.textContent = `تم تطبيق قالب "${preset.label}": ${preset.description} القيم الحالية: جوال ${preset.scales.mobile}%، تابلت ${preset.scales.tablet}%، ديسكتوب ${preset.scales.desktop}%.`;
      }
    }

    function setDevice(device) {
      const current = device === 'desktop' || device === 'tablet' ? device : 'mobile';
      preview.dataset.device = current;
      deviceButtons.forEach((button) => {
        const active = button.dataset.previewDeviceBtn === current;
        button.classList.toggle('is-active', active);
        button.setAttribute('aria-pressed', active ? 'true' : 'false');
      });
    }

    function stopVideo() {
      if (!videoEl) return;
      videoEl.pause();
      videoEl.onloadedmetadata = null;
      videoEl.onerror = null;
      videoEl.removeAttribute('src');
      videoEl.load();
    }

    function syncMedia() {
      let source = initialSrc;
      let sourceKind = source ? initialKind : normalizeMediaType(mediaTypeInput?.value);
      const selectedFile = fileInput?.files && fileInput.files[0] ? fileInput.files[0] : null;

      if (selectedFile) {
        releaseObjectUrl();
        objectUrl = URL.createObjectURL(selectedFile);
        source = objectUrl;
        sourceKind = normalizeMediaType(mediaTypeInput?.value);
      }

      if (!source) {
        toggleHidden(placeholderEl, false);
        placeholderEl.textContent = sourceKind === 'video'
          ? 'اختر فيديو لعرضه داخل مساحة الـ hero.'
          : 'اختر صورة لعرضها داخل مساحة الـ hero.';
        toggleHidden(imageEl, true);
        toggleHidden(videoEl, true);
        stopVideo();
        applyFallbackSmartDefaults('empty');
        return;
      }

      toggleHidden(placeholderEl, true);
      if (sourceKind === 'video') {
        toggleHidden(imageEl, true);
        if (videoEl.getAttribute('src') !== source) {
          videoEl.setAttribute('src', source);
          videoEl.load();
        }
        videoEl.onloadedmetadata = () => {
          rememberMediaMeta({
            mediaType: 'video',
            width: videoEl.videoWidth,
            height: videoEl.videoHeight,
            source: selectedFile ? 'file' : 'current',
          });
        };
        videoEl.onerror = () => applyFallbackSmartDefaults(selectedFile ? 'file' : 'current');
        toggleHidden(videoEl, false);
        const playPromise = videoEl.play();
        if (playPromise && typeof playPromise.catch === 'function') {
          playPromise.catch(() => {});
        }
        return;
      }

      stopVideo();
      if (imageEl.getAttribute('src') !== source) {
        imageEl.setAttribute('src', source);
      }
      imageEl.onload = () => {
        rememberMediaMeta({
          mediaType: 'image',
          width: imageEl.naturalWidth,
          height: imageEl.naturalHeight,
          source: selectedFile ? 'file' : 'current',
        });
      };
      imageEl.onerror = () => applyFallbackSmartDefaults(selectedFile ? 'file' : 'current');
      toggleHidden(imageEl, false);
      toggleHidden(videoEl, true);
    }

    titleInput?.addEventListener('input', syncTitle);
    mediaTypeInput?.addEventListener('change', () => {
      applyFallbackSmartDefaults('type');
      syncMedia();
    });
    fileInput?.addEventListener('change', syncMedia);
    mobileScaleInput?.addEventListener('input', () => {
      syncScale(mobileScaleInput, '--mobile-scale', mobileScaleOutputs, mobileScaleMetric, mobileMin, mobileMax, defaultMobile);
    });
    tabletScaleInput?.addEventListener('input', () => {
      syncScale(tabletScaleInput, '--tablet-scale', tabletScaleOutputs, tabletScaleMetric, tabletMin, tabletMax, defaultTablet);
    });
    desktopScaleInput?.addEventListener('input', () => {
      syncScale(desktopScaleInput, '--desktop-scale', desktopScaleOutputs, desktopScaleMetric, desktopMin, desktopMax, defaultDesktop);
    });
    deviceButtons.forEach((button) => {
      button.addEventListener('click', () => setDevice(button.dataset.previewDeviceBtn));
    });
    smartDefaultsApplyButton?.addEventListener('click', () => {
      applySmartDefaults(true);
    });

    mobileScaleInput?.addEventListener('change', () => {
      manualScaleState.mobile = true;
      setPresetButtonState('');
    });
    tabletScaleInput?.addEventListener('change', () => {
      manualScaleState.tablet = true;
      setPresetButtonState('');
    });
    desktopScaleInput?.addEventListener('change', () => {
      manualScaleState.desktop = true;
      setPresetButtonState('');
    });
    presetButtons.forEach((button) => {
      button.addEventListener('click', () => {
        applyPreset(button.dataset.smartPreset || '');
      });
    });
    editor.addEventListener('submit', releaseObjectUrl, { once: true });

    syncTitle();
    syncScale(mobileScaleInput, '--mobile-scale', mobileScaleOutputs, mobileScaleMetric, mobileMin, mobileMax, defaultMobile);
    syncScale(tabletScaleInput, '--tablet-scale', tabletScaleOutputs, tabletScaleMetric, tabletMin, tabletMax, defaultTablet);
    syncScale(desktopScaleInput, '--desktop-scale', desktopScaleOutputs, desktopScaleMetric, desktopMin, desktopMax, defaultDesktop);
    if (smartDefaultsSummary) {
      smartDefaultsSummary.textContent = buildSummaryText();
    }
    if (smartPresetSummary) {
      smartPresetSummary.textContent = 'اختر قالبًا جاهزًا لتعبئة القياسات مباشرة، ثم عدل يدويًا إذا احتجت.';
    }
    syncMedia();
    setDevice(preview.dataset.defaultDevice || 'mobile');
  }

  document.addEventListener('DOMContentLoaded', () => {
    document.querySelectorAll('[data-banner-editor]').forEach(initBannerEditor);
  });
})();
