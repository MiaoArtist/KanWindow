// 窥窗 · B站全面封锁（他律模式，v3）
// 只保留：搜索框 / 搜索结果列表 / 播放器 / 评论区。
// 其余一切（信息流、热搜、分区、动态、排行榜、UP主区、点赞条、简介、相关推荐、
// “接下来播放”、分P选集、footer 等）一律删除，并持续轮询+观察，删除后自动再删。
// v3：修正播放页判定方向（判断“块是否包含播放器”而不是“播放器包含块”），
//     播放器未渲染前一律不动 —— 宁可漏删，绝不误删播放器。
(function () {
  'use strict';

  var host = location.hostname.toLowerCase();
  if (host !== 'www.bilibili.com' && host !== 'search.bilibili.com' && host !== 'bilibili.com') return;

  var hide = function (el) {
    if (!el || !el.style) return;
    try { el.style.setProperty('display', 'none', 'important'); } catch (e) {}
  };
  var remove = function (el) {
    if (!el || !el.parentNode) return;
    try { el.parentNode.removeChild(el); } catch (e) {}
  };

  var isHome = function () { return location.pathname === '/' || location.pathname === ''; };
  var isWatch = function () { return /^\/video\//.test(location.pathname); };
  var isSearch = function () { return host.indexOf('search.') === 0; };

  var KILL_TEXTS = ['相关推荐', '接下来播放', '热门视频', '为你推荐', '更多视频'];

  // 文本匹配：标题法删除命中区块（只查标题类节点，性能可控）
  function killByText() {
    var nodes = document.querySelectorAll('h2, h3, .section-title, .title, [class*="section-title"], [class*="panel-title"]');
    nodes.forEach(function (h) {
      var t = (h.textContent || '').trim();
      for (var i = 0; i < KILL_TEXTS.length; i++) {
        if (t === KILL_TEXTS[i] || t.indexOf(KILL_TEXTS[i]) === 0) {
          var c = h.closest('section, article, [class*="recommend"], [class*="reco"], #bottom-reco, [class*="panel"]');
          hide(c);
          break;
        }
      }
    });
    // 热搜 / 大家都在搜（限定在容器类里找，不做全局扫描）
    ['大家都在搜', '热门搜索', '热搜榜', '热搜'].forEach(function (txt) {
      document.querySelectorAll('[class*="hot"], [class*="sug"], [class*="suggestion"], [class*="panel"], [class*="rank"]')
        .forEach(function (el) {
          var t = (el.textContent || '').trim();
          if (t === txt || t.indexOf(txt) === 0) hide(el.closest('[class*="hot"]') || el);
        });
    });
  }

  // 顶栏瘦身：删左侧导航与右侧入口整组；搜索框找不到时宁可保留顶栏，绝不误删搜索框
  function slimHeader() {
    document.querySelectorAll('.bili-header__bar .left-entry, .bili-header__bar .right-entry, .left-entry, .right-entry')
      .forEach(hide);
    document.querySelectorAll('[class*="header"] a').forEach(function (a) {
      var t = (a.textContent || '').trim();
      var href = (a.getAttribute('href') || '');
      if (/直播|番剧|游戏中心|会员购|赛事|漫画|课堂|动态|收藏|历史|稍后再看|充电|消息|创作/.test(t)) {
        hide(a.closest('li') || a);
      }
      if (/\/\/space\.bilibili\.com|\/\/t\.bilibili\.com|user\.bilibili/.test(href)) {
        hide(a.closest('li') || a);
      }
    });
    // 搜索框下的“大家都在搜”热词条
    document.querySelectorAll('[class*="sug"] li, [class*="hot-word"], [class*="search-history"]')
      .forEach(function (el) {
        var t = (el.textContent || '').trim();
        if (t.indexOf('大家都在搜') === 0 || t.indexOf('热搜') === 0 || t.indexOf('历史搜索') === 0) {
          hide(el.closest('[class*="sug"], [class*="panel"], [class*="suggestion"]') || el);
        }
      });
  }

  // 首页：保留顶栏（只剩搜索框），其下全部推荐流/分区/排行榜整体删除
  function cleanHome() {
    slimHeader();
    var feed = document.querySelector('.bili-feed4');
    if (feed) {
      var hdr = feed.querySelector('.bili-header') || feed.firstElementChild;
      var sib = hdr ? hdr.nextElementSibling : null;
      while (sib) { var n = sib; sib = sib.nextElementSibling; remove(n); }
    }
    document.querySelectorAll('[class*="channel-nav"], [class*="regions"], [class*="rank"], [id*="rank"], [class*="pop-links"], [class*="channel"]')
      .forEach(remove);
    killByText();
    try {
      var q = document.querySelector('.bili-header__bar input, .bili-header input[type="search"], .nav-search-input');
      if (q && document.activeElement !== q) q.focus();
    } catch (e) {}
  }

  // 搜索页：删热搜/筛选tab，只留结果列表与排序
  function cleanSearch() {
    slimHeader();
    killByText();
    document.querySelectorAll('[class*="filter"] li, [class*="search-tabs"] li, [class*="tabs"] li, [class*="tab-item"]')
      .forEach(function (li) {
        var t = (li.textContent || '').trim();
        if (/番剧|影视|直播|用户|专栏|话题|图集/.test(t)) hide(li);
      });
    document.querySelectorAll('[class*="hot-search"], [class*="search-hot"], [class*="hot-list"], [class*="rank-list"], [id*="hotSearch"]')
      .forEach(hide);
  }

  // 播放页：只留播放器 + 评论区
  function cleanWatch() {
    slimHeader();
    var player = document.querySelector('#bpx-player-wrap, #bofqi, .bpx-player-container, [class*="bpx-player"]');
    if (!player) return;   // 播放器还没渲染出来之前一律不动，绝不误删

    var comments = document.querySelector('#comment-app, #comment, .comment-container, [class*="comment-app"], [class*="comment"]');

    // 主内容区：只保留“包含播放器”和“包含评论区”的块，其余整块隐藏
    // （找齐评论区后才做整块清理，避免误删；评论区晚渲染时由轮询兜底）
    if (comments) {
      document.querySelectorAll('#biliMainContent, #video-page-app, [class*="video-container-v1"], [class*="video-container"]')
        .forEach(function (c) {
          if (!c || !c.children) return;
          var kids = Array.prototype.slice.call(c.children);
          kids.forEach(function (el) {
            if (!el || !el.contains) return;
            if (el === player || el.contains(player)) return;
            if (el === comments || el.contains(comments)) return;
            hide(el);
          });
        });
    }

    // 黑名单兜底（结构变化时也能删掉已知噪音块）
    var sels = [
      '#reco_list', '#recommend_list', '#relevant_recommendation',
      '.recommend-list-v1', '.rec-footer', '#bottom-reco',
      '#biliMainContent .right-container', '.video-card-v1',
      '[class*="videoRecommend"]', '[class*="recommend-swipe"]', '[class*="more-video"]',
      '[class*="up-info"]', '[class*="up-panel"]',
      '[class*="video-toolbar"]', '.ops', '[class*="toolbar"]',
      '[class*="video-desc"]', '[class*="tag-panel"]', '[class*="tags"]',
      '[class*="ep-list"]', '[class*="multi-page"]', '[class*="part-list"]',
      '[class*="video-title"]',
      '.bili-footer', 'footer'
    ];
    sels.forEach(function (s) {
      try { document.querySelectorAll(s).forEach(hide); } catch (e) {}
    });
    killByText();
  }

  function clean() {
    if (isHome()) cleanHome();
    else if (isWatch()) cleanWatch();
    else if (isSearch()) cleanSearch();
    else slimHeader();
  }

  clean();
  new MutationObserver(function () {
    try { clean(); } catch (e) {}
  }).observe(document.documentElement, { childList: true, subtree: true });
  setInterval(function () { try { clean(); } catch (e) {} }, 800);
})();