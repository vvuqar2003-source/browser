(function() {
    'use strict';

    const VIDEO_EXTENSIONS = ['mp4', 'm3u8', 'mkv', 'webm', 'ts', 'mov', 'avi', 'flv', 'wmv', '3gp'];
    const SUBTITLE_EXTENSIONS = ['vtt', 'srt', 'ass', 'ssa', 'sub'];
    const sentURLs = new Set();

    function isVideoURL(url) {
        try {
            const pathname = new URL(url).pathname.toLowerCase();
            const ext = pathname.split('.').pop();
            const clean = ext.includes('?') ? ext.split('?')[0] : ext;
            return VIDEO_EXTENSIONS.includes(clean);
        } catch { return false; }
    }

    function isSubtitleURL(url) {
        try {
            const pathname = new URL(url).pathname.toLowerCase();
            const ext = pathname.split('.').pop();
            const clean = ext.includes('?') ? ext.split('?')[0] : ext;
            return SUBTITLE_EXTENSIONS.includes(clean);
        } catch { return false; }
    }

    function sendURL(url, type, streamType) {
        if (sentURLs.has(url)) return;
        sentURLs.add(url);
        try {
            const msg = {
                url: url,
                pageTitle: document.title || '',
                type: type
            };
            if (streamType) msg.streamType = streamType;
            window.webkit.messageHandlers.videoFound.postMessage(msg);
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

    // Force-send a URL as video regardless of extension (used by player hooks)
    function sendPlayerSource(url, streamType) {
        if (!url || typeof url !== 'string') return;
        if (sentURLs.has(url)) return;
        try {
            const resolved = new URL(url, document.baseURI).href;
            sendURL(resolved, 'video', streamType || 'direct');
        } catch(e) {}
    }

    // Detect HLS stream type from player config object
    function getStreamType(obj) {
        if (!obj) return 'direct';
        const t = String(obj.type || '').toLowerCase();
        if (t === 'hls' || t.includes('mpegurl') || t === 'm3u8') return 'hls';
        const f = String(obj.file || obj.src || '');
        if (f.includes('.m3u8')) return 'hls';
        return 'direct';
    }

    // Extract sources from player config (JWPlayer format)
    function extractSources(config) {
        if (!config) return;
        if (config.file) sendPlayerSource(config.file, getStreamType(config));
        if (config.src) sendPlayerSource(config.src, getStreamType(config));
        (config.sources || []).forEach(function(s) {
            var u = s.file || s.src;
            if (u) sendPlayerSource(u, getStreamType(s));
        });
        (config.playlist || []).forEach(function(item) {
            if (item.file) sendPlayerSource(item.file, getStreamType(item));
            if (item.src) sendPlayerSource(item.src, getStreamType(item));
            (item.sources || []).forEach(function(s) {
                var u = s.file || s.src;
                if (u) sendPlayerSource(u, getStreamType(s));
            });
        });
    }

    // ==========================================
    // JWPlayer Hook
    // ==========================================
    function hookJWPlayer(jw) {
        if (!jw || typeof jw !== 'function' || jw.__bapp) return jw;

        var wrapped = function() {
            var player = jw.apply(this, arguments);
            if (player && typeof player.setup === 'function' && !player.__bapp_hooked) {
                var origSetup = player.setup;
                player.setup = function(config) {
                    extractSources(config);
                    var result = origSetup.call(this, config);
                    // Also catch playlist changes
                    try {
                        this.on('playlistItem', function(e) {
                            if (e && e.item) extractSources(e.item);
                        });
                    } catch(ex) {}
                    return result;
                };
                // Also hook on('ready') to get current source
                try {
                    var origOn = player.on;
                    if (origOn) {
                        player.on = function(evt, cb) {
                            var result = origOn.call(this, evt, cb);
                            return result;
                        };
                    }
                } catch(ex) {}
                player.__bapp_hooked = true;
            }
            return player;
        };

        // Copy static properties (jwplayer.key, jwplayer.version, etc.)
        for (var key in jw) {
            try { if (jw.hasOwnProperty(key)) wrapped[key] = jw[key]; } catch(e) {}
        }
        wrapped.__bapp = true;
        return wrapped;
    }

    // Install JWPlayer trap
    var _jw = window.jwplayer;
    if (_jw) _jw = hookJWPlayer(_jw);
    try {
        Object.defineProperty(window, 'jwplayer', {
            get: function() { return _jw; },
            set: function(val) {
                _jw = (typeof val === 'function') ? hookJWPlayer(val) : val;
            },
            configurable: true,
            enumerable: true
        });
    } catch(e) {
        if (window.jwplayer) window.jwplayer = hookJWPlayer(window.jwplayer);
    }

    // ==========================================
    // Playerjs / Pljssgn Hook (common on Turkish sites)
    // ==========================================
    var _playerjs = window.Playerjs;
    function hookPlayerjs(PJS) {
        if (!PJS || typeof PJS !== 'function' || PJS.__bapp) return PJS;
        var wrapped = function(config) {
            if (config) {
                if (config.file) sendPlayerSource(config.file, getStreamType(config));
                (config.sources || []).forEach(function(s) {
                    var u = s.file || s.src;
                    if (u) sendPlayerSource(u, getStreamType(s));
                });
            }
            return new PJS(config);
        };
        wrapped.prototype = PJS.prototype;
        wrapped.__bapp = true;
        return wrapped;
    }
    try {
        Object.defineProperty(window, 'Playerjs', {
            get: function() { return _playerjs; },
            set: function(val) {
                _playerjs = (typeof val === 'function') ? hookPlayerjs(val) : val;
            },
            configurable: true,
            enumerable: true
        });
    } catch(e) {}

    // ==========================================
    // Video.js Hook
    // ==========================================
    var _videojs = window.videojs;
    function hookVideojs(vjs) {
        if (!vjs || typeof vjs !== 'function' || vjs.__bapp) return vjs;
        var wrapped = function() {
            var player = vjs.apply(this, arguments);
            if (player) {
                try {
                    var origSrc = player.src;
                    if (typeof origSrc === 'function') {
                        player.src = function(source) {
                            if (source) {
                                if (typeof source === 'string') sendPlayerSource(source, 'direct');
                                else if (source.src) sendPlayerSource(source.src, getStreamType(source));
                                else if (Array.isArray(source)) {
                                    source.forEach(function(s) {
                                        if (s.src) sendPlayerSource(s.src, getStreamType(s));
                                    });
                                }
                            }
                            return origSrc.apply(this, arguments);
                        };
                    }
                } catch(ex) {}
            }
            return player;
        };
        for (var key in vjs) {
            try { if (vjs.hasOwnProperty(key)) wrapped[key] = vjs[key]; } catch(e) {}
        }
        wrapped.__bapp = true;
        return wrapped;
    }
    try {
        Object.defineProperty(window, 'videojs', {
            get: function() { return _videojs; },
            set: function(val) {
                _videojs = (typeof val === 'function') ? hookVideojs(val) : val;
            },
            configurable: true,
            enumerable: true
        });
    } catch(e) {}

    // ==========================================
    // Fetch & XHR intercept (check response content-type too)
    // ==========================================
    var originalFetch = window.fetch;
    window.fetch = function() {
        var url = typeof arguments[0] === 'string' ? arguments[0] : (arguments[0] && arguments[0].url);
        if (url) checkAllTypes(url);

        return originalFetch.apply(this, arguments).then(function(response) {
            try {
                var ct = response.headers.get('content-type') || '';
                var respUrl = response.url || url;
                if (ct.includes('mpegurl') || ct.includes('application/vnd.apple')) {
                    sendPlayerSource(respUrl, 'hls');
                } else if (ct.includes('video/') || ct.includes('application/octet-stream')) {
                    // Check if it's actually video by URL pattern
                    if (respUrl && !isVideoURL(respUrl)) {
                        sendPlayerSource(respUrl, 'direct');
                    }
                }
            } catch(e) {}
            return response;
        });
    };

    var originalXHROpen = XMLHttpRequest.prototype.open;
    var originalXHRSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, url) {
        this._bapp_url = url;
        if (url) checkAllTypes(typeof url === 'string' ? url : String(url));
        return originalXHROpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function() {
        var xhr = this;
        var origOnReady = xhr.onreadystatechange;
        xhr.addEventListener('load', function() {
            try {
                var ct = xhr.getResponseHeader('content-type') || '';
                if (ct.includes('mpegurl') || ct.includes('application/vnd.apple')) {
                    sendPlayerSource(xhr._bapp_url || xhr.responseURL, 'hls');
                }
            } catch(e) {}
        });
        return originalXHRSend.apply(this, arguments);
    };

    // ==========================================
    // HTMLMediaElement src hook
    // ==========================================
    try {
        var srcDescriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
        if (srcDescriptor && srcDescriptor.set) {
            Object.defineProperty(HTMLMediaElement.prototype, 'src', {
                get: function() { return srcDescriptor.get.call(this); },
                set: function(value) {
                    if (value) checkAllTypes(value);
                    srcDescriptor.set.call(this, value);
                }
            });
        }
    } catch(e) {}

    // ==========================================
    // DOM scanning
    // ==========================================
    function scanElement(el) {
        if (!el || !el.tagName) return;

        for (var i = 0; i < (el.attributes || []).length; i++) {
            var attr = el.attributes[i];
            if (attr.value && typeof attr.value === 'string' && attr.value.length > 5) {
                checkAllTypes(attr.value);
            }
        }

        if (el.tagName === 'VIDEO' || el.tagName === 'AUDIO') {
            if (el.src) checkAllTypes(el.src);
            if (el.currentSrc) checkAllTypes(el.currentSrc);
            el.querySelectorAll('source').forEach(function(s) {
                if (s.src) checkAllTypes(s.src);
                if (s.getAttribute('data-src')) checkAllTypes(s.getAttribute('data-src'));
            });
        }

        if (el.tagName === 'TRACK' && el.src) checkAllTypes(el.src);
        if (el.tagName === 'A' && el.href && el.href !== document.location.href) checkAllTypes(el.href);

        if (el.tagName === 'IFRAME' && el.src) {
            checkAllTypes(el.src);
            try {
                var doc = el.contentDocument || (el.contentWindow && el.contentWindow.document);
                if (doc) doc.querySelectorAll('video, audio, source, track, a[href], [src]').forEach(scanElement);
            } catch(e) {}
        }
    }

    window.manualScan = function() {
        document.querySelectorAll('*').forEach(scanElement);

        // Also poll active player instances
        try {
            if (window.jwplayer) {
                var p = window.jwplayer();
                if (p && p.getPlaylistItem) {
                    var item = p.getPlaylistItem();
                    if (item) extractSources(item);
                }
                if (p && p.getConfig) {
                    var cfg = p.getConfig();
                    if (cfg) extractSources(cfg);
                }
            }
        } catch(e) {}

        // Check for Playerjs instances
        try {
            var players = document.querySelectorAll('[id*="player"], [class*="player"], .plyr, .jw-video, .vjs-tech');
            players.forEach(function(el) {
                if (el.tagName === 'VIDEO' || el.tagName === 'AUDIO') {
                    if (el.src) sendPlayerSource(el.src, 'direct');
                    if (el.currentSrc) sendPlayerSource(el.currentSrc, 'direct');
                }
            });
        } catch(e) {}
    };

    // ==========================================
    // MutationObserver
    // ==========================================
    var observer = new MutationObserver(function(mutations) {
        for (var i = 0; i < mutations.length; i++) {
            var mutation = mutations[i];
            for (var j = 0; j < mutation.addedNodes.length; j++) {
                var node = mutation.addedNodes[j];
                if (node.nodeType === Node.ELEMENT_NODE) {
                    scanElement(node);
                    if (node.querySelectorAll) {
                        node.querySelectorAll('*').forEach(scanElement);
                    }
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

    // Initial scan
    document.querySelectorAll('*').forEach(scanElement);

    // Periodic scan for dynamically loaded players
    setInterval(function() {
        // Check video/audio elements
        document.querySelectorAll('video, audio').forEach(function(el) {
            if (el.src) checkAllTypes(el.src);
            if (el.currentSrc) checkAllTypes(el.currentSrc);
            el.querySelectorAll('source').forEach(function(s) {
                if (s.src) checkAllTypes(s.src);
            });
        });

        // Poll JWPlayer
        try {
            if (window.jwplayer) {
                var p = window.jwplayer();
                if (p && p.getPlaylistItem) {
                    var item = p.getPlaylistItem();
                    if (item) extractSources(item);
                }
            }
        } catch(e) {}
    }, 3000);
})();
