// BrowserApp/BrowserApp/VideoDetector/inject.js

(function() {
    'use strict';

    const VIDEO_EXTENSIONS = ['mp4', 'm3u8', 'mkv', 'webm', 'ts', 'mov'];
    const SUBTITLE_EXTENSIONS = ['vtt', 'srt'];
    const sentURLs = new Set();

    function isVideoURL(url) {
        try {
            const pathname = new URL(url).pathname.toLowerCase();
            const ext = pathname.split('.').pop();
            return VIDEO_EXTENSIONS.includes(ext);
        } catch {
            return false;
        }
    }

    function isSubtitleURL(url) {
        try {
            const pathname = new URL(url).pathname.toLowerCase();
            const ext = pathname.split('.').pop();
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
        try {
            const fullURL = new URL(url, document.baseURI).href;
            if (type === 'video' && isVideoURL(fullURL)) {
                sendURL(fullURL, 'video');
            } else if (type === 'subtitle' && isSubtitleURL(fullURL)) {
                sendURL(fullURL, 'subtitle');
            }
        } catch {}
    }

    const originalFetch = window.fetch;
    window.fetch = function(...args) {
        const url = typeof args[0] === 'string' ? args[0] : args[0]?.url;
        if (url) {
            checkURL(url, 'video');
            checkURL(url, 'subtitle');
        }
        return originalFetch.apply(this, args);
    };

    const originalXHROpen = XMLHttpRequest.prototype.open;
    XMLHttpRequest.prototype.open = function(method, url, ...rest) {
        if (url) {
            checkURL(url, 'video');
            checkURL(url, 'subtitle');
        }
        return originalXHROpen.apply(this, [method, url, ...rest]);
    };

    function scanElement(el) {
        if (el.tagName === 'VIDEO' || el.tagName === 'AUDIO') {
            const src = el.src || el.querySelector('source')?.src;
            if (src) checkURL(src, 'video');

            el.querySelectorAll('source').forEach(s => {
                if (s.src) checkURL(s.src, 'video');
            });
        }

        if (el.tagName === 'TRACK') {
            const src = el.src;
            if (src) checkURL(src, 'subtitle');
        }

        if (el.tagName === 'A' && el.href) {
            checkURL(el.href, 'video');
        }

        const style = window.getComputedStyle(el);
        const bg = style.backgroundImage;
        if (bg && bg !== 'none') {
            const match = bg.match(/url\(["']?(.*?)["']?\)/);
            if (match) checkURL(match[1], 'video');
        }
    }

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
        attributeFilter: ['src', 'href', 'style']
    });

    document.querySelectorAll('video, audio, source, track, a[href]').forEach(scanElement);

    setInterval(() => {
        document.querySelectorAll('video, audio').forEach(el => {
            const src = el.src || el.querySelector('source')?.src;
            if (src) checkURL(src, 'video');
        });
    }, 3000);
})();
