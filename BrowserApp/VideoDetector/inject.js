(function() {
    'use strict';

    const VIDEO_EXTENSIONS = ['mp4', 'm3u8', 'mkv', 'webm', 'ts', 'mov', 'avi', 'flv', 'wmv', '3gp'];
    const SUBTITLE_EXTENSIONS = ['vtt', 'srt', 'ass', 'ssa', 'sub'];
    const sentURLs = new Set();

    function isVideoURL(url) {
        try {
            const pathname = new URL(url).pathname.toLowerCase();
            const ext = pathname.split('.').pop();
            if (ext.includes('?')) return VIDEO_EXTENSIONS.includes(ext.split('?')[0]);
            return VIDEO_EXTENSIONS.includes(ext);
        } catch {
            return false;
        }
    }

    function isSubtitleURL(url) {
        try {
            const pathname = new URL(url).pathname.toLowerCase();
            const ext = pathname.split('.').pop();
            if (ext.includes('?')) return SUBTITLE_EXTENSIONS.includes(ext.split('?')[0]);
            return SUBTITLE_EXTENSIONS.includes(ext);
        } catch {
            return false;
        }
    }

    function sendURL(url, type) {
        if (sentURLs.has(url)) return;
        sentURLs.add(url);

        try {
            window.webkit.messageHandlers.videoFound.postMessage({
                url: url,
                pageTitle: document.title || '',
                type: type
            });
        } catch(e) {}
    }

    function checkURL(url, type) {
        if (!url || typeof url !== 'string') return;
        try {
            const fullURL = new URL(url, document.baseURI).href;
            if (type === 'video' && isVideoURL(fullURL)) {
                sendURL(fullURL, 'video');
            } else if (type === 'subtitle' && isSubtitleURL(fullURL)) {
                sendURL(fullURL, 'subtitle');
            }
        } catch {}
    }

    function checkAllTypes(url) {
        checkURL(url, 'video');
        checkURL(url, 'subtitle');
    }

    function scanElement(el) {
        if (!el || !el.tagName) return;

        for (const attr of el.attributes || []) {
            if (attr.value && typeof attr.value === 'string' && attr.value.length > 5) {
                checkAllTypes(attr.value);
            }
        }

        if (el.tagName === 'VIDEO' || el.tagName === 'AUDIO') {
            if (el.src) checkAllTypes(el.src);
            if (el.currentSrc) checkAllTypes(el.currentSrc);
            if (el.poster) checkAllTypes(el.poster);
            el.querySelectorAll('source').forEach(s => {
                if (s.src) checkAllTypes(s.src);
                if (s.getAttribute('data-src')) checkAllTypes(s.getAttribute('data-src'));
            });
        }

        if (el.tagName === 'TRACK' && el.src) {
            checkAllTypes(el.src);
        }

        if (el.tagName === 'A' && el.href) {
            if (el.href !== document.location.href) checkAllTypes(el.href);
        }

        if (el.tagName === 'IFRAME') {
            if (el.src) checkAllTypes(el.src);
            try {
                const doc = el.contentDocument || el.contentWindow?.document;
                if (doc) {
                    doc.querySelectorAll('video, audio, source, track, a[href], [src]').forEach(scanElement);
                }
            } catch(e) {}
        }

        if (el.tagName === 'IMG' && el.src) {
            checkAllTypes(el.src);
        }

        const style = window.getComputedStyle(el);
        const bg = style.backgroundImage;
        if (bg && bg !== 'none') {
            const matches = bg.matchAll(/url\(["']?(.*?)["']?\)/g);
            for (const match of matches) {
                checkAllTypes(match[1]);
            }
        }
    }

    const originalFetch = window.fetch;
    window.fetch = function(...args) {
        const url = typeof args[0] === 'string' ? args[0] : args[0]?.url;
        if (url) checkAllTypes(url);
        return originalFetch.apply(this, args);
    };

    const originalXHROpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url, ...rest) {
        if (url) checkAllTypes(url);
        return originalXHROpen.apply(this, [method, url, ...rest]);
    };

    try {
        const srcDescriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
        if (srcDescriptor && srcDescriptor.set) {
            Object.defineProperty(HTMLMediaElement.prototype, 'src', {
                get() { return srcDescriptor.get.call(this); },
                set(value) {
                    if (value) checkAllTypes(value);
                    srcDescriptor.set.call(this, value);
                }
            });
        }
    } catch(e) {}

    window.manualScan = function() {
        document.querySelectorAll('*').forEach(scanElement);
    };

    const observer = new MutationObserver((mutations) => {
        for (const mutation of mutations) {
            for (const node of mutation.addedNodes) {
                if (node.nodeType === Node.ELEMENT_NODE) {
                    scanElement(node);
                    node.querySelectorAll?.('*')?.forEach(scanElement);
                }
            }
            if (mutation.type === 'attributes') {
                scanElement(mutation.target);
            }
        }
    });

    observer.observe(document.documentElement, {
        childList: true,
        subtree: true,
        attributes: true,
        attributeFilter: ['src', 'href', 'style', 'data-src', 'data-url', 'poster']
    });

    document.querySelectorAll('*').forEach(scanElement);

    setInterval(() => {
        document.querySelectorAll('video, audio').forEach(el => {
            if (el.src) checkAllTypes(el.src);
            if (el.currentSrc) checkAllTypes(el.currentSrc);
            el.querySelectorAll('source').forEach(s => {
                if (s.src) checkAllTypes(s.src);
            });
        });
    }, 3000);
})();
