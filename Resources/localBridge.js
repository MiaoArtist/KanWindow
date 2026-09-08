// 窥窗 · 本地服务桥（webui 支持）v2 —— 透明代理版
// 把页面里对 http://127.0.0.1:* / http://localhost:* 的 fetch / XHR 请求
// 改写为 kwlocal://fetch?…（自定义 scheme），由 App 转发并放行 CORS。
// v2 要点：
//  - fetch：仅本地地址才改道，其余原样透传（含流式响应）；
//  - XHR：完整保留原生能力（responseType/abort/upload/事件等），
//    仅“本地 + 异步”走桥；本地同步请求走原生直连兜底；
//  - 不再整体替换 XHR 导致站点脚本崩溃。
(function () {
  'use strict';
  if (window.__kwLocalBridged) return;
  window.__kwLocalBridged = true;

  function isLocalHttp(u) {
    return /^https?:\/\/(127\.0\.0\.1|localhost|\[::1\]|::1)(:\d+)?($|\/)/i.test(String(u || ''));
  }
  function b64str(s) {
    try { return btoa(unescape(encodeURIComponent(s))); } catch (e) { return ''; }
  }
  function b64bytes(u8) {
    var bin = '';
    for (var i = 0; i < u8.length; i++) bin += String.fromCharCode(u8[i]);
    try { return btoa(bin); } catch (e) { return ''; }
  }
  function b64(s) {
    if (s == null) return '';
    if (typeof s === 'string') return b64str(s);
    if (typeof ArrayBuffer !== 'undefined' && s instanceof ArrayBuffer) return b64bytes(new Uint8Array(s));
    if (typeof ArrayBuffer !== 'undefined' && ArrayBuffer.isView && ArrayBuffer.isView(s)) {
      return b64bytes(new Uint8Array(s.buffer, s.byteOffset, s.byteLength));
    }
    if (typeof s === 'object') { try { return b64str(JSON.stringify(s)); } catch (e) { return ''; } }
    return '';
  }
  function headersToObj(h) {
    if (!h) return {};
    if (typeof Headers !== 'undefined' && h instanceof Headers) {
      var o = {};
      h.forEach(function (v, k) { o[k] = v; });
      return o;
    }
    return h;
  }

  var origFetch = window.fetch;
  function go(url, method, headers, body) {
    var q = 'kwlocal://fetch?u=' + encodeURIComponent(url)
      + '&m=' + encodeURIComponent(method || 'GET')
      + '&h=' + encodeURIComponent(JSON.stringify(headersToObj(headers)))
      + '&b=' + encodeURIComponent(b64(body));
    return origFetch(q, { method: 'GET', credentials: 'omit', cache: 'no-store' });
  }

  // ---- fetch：仅本地地址改道 ----
  window.fetch = function (input, init) {
    var url = '';
    try { url = typeof input === 'string' ? input : (input && input.url) || ''; } catch (e) {}
    if (typeof input === 'string' && isLocalHttp(url)) {
      return go(url, init && init.method, init && init.headers, init && init.body);
    }
    return origFetch.apply(this, arguments);
  };

  // ---- XHR：透明代理 ----
  var OXHR = window.XMLHttpRequest;
  function KWXHR() {
    var self = this;
    self.__m = 'GET';
    self.__u = '';
    self.__h = {};
    self.__async = true;
    self.__wrapped = false;

    // 常用属性（与原生默认一致）
    self.readyState = 0;
    self.status = 0;
    self.statusText = '';
    self.responseURL = '';
    self.responseType = '';
    self.timeout = 0;
    self.withCredentials = false;
    self.upload = {};
    self.onreadystatechange = null;
    self.onload = null;
    self.onerror = null;
    self.onloadend = null;
    self.onprogress = null;
    self.onabort = null;
    self.ontimeout = null;

    self.open = function (m, u, async) {
      self.__m = (String(m || 'GET')).toUpperCase();
      self.__u = String(u || '');
      self.__async = async !== false;
      self.__wrapped = isLocalHttp(self.__u);
      self.readyState = 1;
    };
    self.setRequestHeader = function (k, v) { self.__h[k] = String(v); };
    self.getResponseHeader = function () { return null; };
    self.getAllResponseHeaders = function () { return ''; };
    self.overrideMimeType = function () {};
    self.abort = function () {
      self.readyState = 0;
      self.status = 0;
      if (self.onabort) { try { self.onabort.call(self); } catch (e) {} }
      if (self.onloadend) { try { self.onloadend.call(self); } catch (e) {} }
    };

    self.send = function (body) {
      // 非本地：透传原生（保留响应/事件/能力完全一致）
      if (!self.__wrapped) {
        var raw = new OXHR();
        raw.open(self.__m, self.__u, self.__async);
        for (var k in self.__h) { try { raw.setRequestHeader(k, self.__h[k]); } catch (e) {} }
        raw.onreadystatechange = function () {
          self.readyState = raw.readyState;
          if (raw.readyState === 4) {
            self.status = raw.status;
            self.statusText = raw.statusText;
            self.responseURL = raw.responseURL;
            try {
              Object.defineProperty(self, 'responseText', { get: function () { return raw.responseText; }, configurable: true });
              Object.defineProperty(self, 'response', { get: function () { return raw.response; }, configurable: true });
            } catch (e) {}
          }
          if (self.onreadystatechange) { try { self.onreadystatechange.call(self); } catch (e) {} }
        };
        var forward = function (evName, cbName) {
          raw[evName] = function (ev) { if (self[cbName]) { try { self[cbName].call(self, ev); } catch (e) {} } };
        };
        forward('onload', 'onload');
        forward('onerror', 'onerror');
        forward('onloadend', 'onloadend');
        forward('onprogress', 'onprogress');
        forward('onabort', 'onabort');
        forward('ontimeout', 'ontimeout');
        raw.send(body);
        return;
      }

      // 本地 + 同步：走原生直连（WKWebView 桥无法同步返回）
      if (!self.__async) {
        var raw2 = new OXHR();
        raw2.open(self.__m, self.__u, false);
        for (var k2 in self.__h) { try { raw2.setRequestHeader(k2, self.__h[k2]); } catch (e) {} }
        try { raw2.send(body); } catch (e) {}
        self.readyState = 4;
        self.status = raw2.status;
        self.statusText = raw2.statusText;
        self.responseURL = self.__u;
        try {
          Object.defineProperty(self, 'responseText', { get: function () { return raw2.responseText; }, configurable: true });
          Object.defineProperty(self, 'response', { get: function () { return raw2.response; }, configurable: true });
        } catch (e) {}
        if (self.onreadystatechange) { try { self.onreadystatechange.call(self); } catch (e) {} }
        if (self.onload) { try { self.onload.call(self); } catch (e) {} }
        return;
      }

      // 本地 + 异步：走 kwlocal 桥
      go(self.__u, self.__m, self.__h, body).then(function (resp) {
        return resp.text().then(function (txt) {
          self.status = resp.status;
          self.statusText = resp.statusText || '';
          self.responseURL = self.__u;
          try {
            Object.defineProperty(self, 'responseText', { get: function () { return txt; }, configurable: true });
            Object.defineProperty(self, 'response', {
              get: function () {
                if (self.responseType === 'json') { try { return JSON.parse(txt); } catch (e) { return null; } }
                return txt;
              },
              configurable: true
            });
          } catch (e) {}
          self.readyState = 4;
          if (self.onreadystatechange) { try { self.onreadystatechange.call(self); } catch (e) {} }
          if (self.onload) { try { self.onload.call(self); } catch (e) {} }
          if (self.onloadend) { try { self.onloadend.call(self); } catch (e) {} }
        });
      }).catch(function (err) {
        self.readyState = 4;
        self.status = 0;
        if (self.onerror) { try { self.onerror.call(self, err); } catch (e) {} }
        if (self.onloadend) { try { self.onloadend.call(self); } catch (e) {} }
      });
      if (this.onloadstart) { try { this.onloadstart.call(this); } catch (e) {} }
    };
  }
  window.XMLHttpRequest = KWXHR;
  window.XMLHttpRequest.prototype = OXHR.prototype;
})();