// 窥窗 · 本地服务桥（webui 支持）
// 把页面里对 http://127.0.0.1:* / http://localhost:* 的 fetch / XHR 请求
// 改写为 kwlocal://fetch?…（自定义 scheme），由 App 转发并放行 CORS。
// 这样 AnkiConnect（127.0.0.1:8765）、Stable Diffusion WebUI、Jupyter 等
// 本机 WebUI 在窥窗里也能像在 Chrome 里一样工作。
(function () {
  'use strict';
  if (window.__kwLocalBridged) return;
  window.__kwLocalBridged = true;

  function isLocalHttp(u) {
    return /^https?:\/\/(127\.0\.0\.1|localhost|\[::1\]|::1)(:\d+)?($|\/)/i.test(String(u || ''));
  }
  function b64(s) {
    try { return btoa(unescape(encodeURIComponent(String(s == null ? '' : s)))); }
    catch (e) { return ''; }
  }
  function go(url, method, headers, body) {
    var q = 'kwlocal://fetch'
      + '?u=' + encodeURIComponent(url)
      + '&m=' + encodeURIComponent(method || 'GET')
      + '&h=' + encodeURIComponent(JSON.stringify(headers || {}))
      + '&b=' + encodeURIComponent(b64(body));
    return fetch(q, { method: 'GET', credentials: 'omit', cache: 'no-store' });
  }

  // ---- fetch ----
  var origFetch = window.fetch;
  window.fetch = function (input, init) {
    var url = typeof input === 'string' ? input : (input && input.url) || '';
    if (typeof input === 'string' && isLocalHttp(url)) {
      return go(url, init && init.method, init && init.headers, init && init.body);
    }
    return origFetch.apply(this, arguments);
  };

  // ---- XMLHttpRequest（axios 等基于 XHR 的库也能用）----
  var OXHR = window.XMLHttpRequest;
  function KWXHR() {
    var x = new OXHR();
    var reqUrl = '', reqMethod = 'GET', reqHeaders = {}, reqAsync = true, wrapped = false;

    x.open = function (m, u, async, user, pass) {
      reqMethod = (m || 'GET').toUpperCase();
      reqUrl = String(u || '');
      reqAsync = async !== false;
      wrapped = isLocalHttp(reqUrl);
      if (wrapped) {
        // 用占位地址先占住 open 状态，真正的请求在 send 里走本地桥
        OXHR.prototype.open.call(x, 'GET', 'kwlocal://fetch?u=&m=GET&h={}&b=', true);
      } else {
        var args = Array.prototype.slice.call(arguments);
        return OXHR.prototype.open.apply(x, args);
      }
    };
    x.setRequestHeader = function (k, v) { reqHeaders[k] = String(v); };
    x.send = function (body) {
      if (!wrapped) return OXHR.prototype.send.call(x, body);
      var self = this;
      go(reqUrl, reqMethod, reqHeaders, body).then(function (resp) {
        self.status = resp.status;
        self.statusText = resp.statusText || '';
        return resp.text().then(function (txt) {
          self.responseText = txt;
          self.response = txt;
          self.responseURL = reqUrl;
          self.readyState = 4;
          if (self.onreadystatechange) { try { self.onreadystatechange.call(self); } catch (e) {} }
          if (self.onload) { try { self.onload.call(self); } catch (e) {} }
          if (self.onloadend) { try { self.onloadend.call(self); } catch (e) {} }
        });
      }).catch(function (err) {
        self.status = 0;
        self.readyState = 4;
        if (self.onerror) { try { self.onerror.call(self, err); } catch (e) {} }
        if (self.onloadend) { try { self.onloadend.call(self); } catch (e) {} }
      });
      // 同步模式不支持本地桥，退化为异步（浏览器对本地请求本来就多异步）
    };
    return x;
  }
  window.XMLHttpRequest = KWXHR;
  window.XMLHttpRequest.prototype = OXHR.prototype;
})();