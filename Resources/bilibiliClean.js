// 窥窗 · B站页面清理（他律模式）
// 思路参照油猴脚本「哔哩哔哩页面清理」：在原生 bilibili 站点上注入清理，
// 只砍掉“信息流/推荐/入口”，保留搜索、播放器（画质/倍速/弹幕）、封面与评论区。
// 注入到所有 bilibili.com 页面 —— 站内任何跳转都处于清理范围内，不会被“打回原形”。
(function () {
  'use strict';

  if (!/^(www\.)?bilibili\.com$/i.test(location.hostname)) return;

  var hide = function (el) {
    try { el.style.setProperty('display', 'none', 'important'); } catch (e) {}
  };

  // 1) 导航栏清理：只留 首页/搜索，隐藏娱乐入口与个人中心入口
  var LEFT_ENTRIES = ['番剧', '直播', '游戏中心', '会员购', '赛事', '漫画', '课堂', '活动', '影库', '音乐', '时尚'];
  var RIGHT_ENTRIES = ['动态', '收藏', '历史', '创作中心', '消息', '稍后再看', '充电', '直播中心', '稿件管理', '小黑屋'];

  function cleanNav() {
    document.querySelectorAll('.bili-header__bar .left-entry a, .left-entry a.default-entry, .nav-menu a, #nav a')
      .forEach(function (a) {
        var t = (a.textContent || '').trim();
        if (LEFT_ENTRIES.indexOf(t) >= 0) {
          hide(a.closest('li') || a.parentElement);
        }
      });
    document.querySelectorAll('.bili-header__bar .right-entry a, .right-entry a')
      .forEach(function (a) {
        var t = (a.textContent || '').trim();
        if (RIGHT_ENTRIES.indexOf(t) >= 0) {
          hide(a.closest('li') || a.parentElement);
        }
      });
  }

  // 2) 首页：保留顶栏（logo+搜索框），清掉其下全部推荐流
  function cleanHome() {
    var feed = document.querySelector('.bili-feed4');
    if (!feed) return;
    var hdr = feed.querySelector('.bili-header') || feed.firstElementChild;
    if (!hdr) return;
    var sib = hdr.nextElementSibling;
    while (sib) { var n = sib; sib = sib.nextElementSibling; hide(n); }
    // 聚焦搜索框
    try {
      var q = document.querySelector('.bili-header input[type="search"], .bili-header .search-input, #biliMainHeader input[type="search"], .nav-search-input');
      if (q && document.activeElement !== q) q.focus();
    } catch (e) {}
  }

  // 3) 播放页：保留播放器/评论区，隐藏相关推荐与“接下来播放”
  function cleanWatch() {
    var sels = [
      '#reco_list', '#recommend_list', '#relevant_recommendation',
      '.recommend-list-v1', '.rec-footer', '#bottom-reco',
      '#biliMainContent .right-container', '.video-card-v1',
      '[class*="videoRecommend"]', '[class*="recommend-swipe"]',
      '[class*="more-video"]'
    ];
    sels.forEach(function (s) {
      try { document.querySelectorAll(s).forEach(hide); } catch (e) {}
    });
    // 文本匹配兜底（B 站改版时选择器变化也兜得住）
    var titles = ['相关推荐', '接下来播放', '热门视频', '为你推荐', '更多视频'];
    document.querySelectorAll('h2, h3, .section-title, [class*="section-title"]')
      .forEach(function (h) {
        var t = (h.textContent || '').trim();
        for (var i = 0; i < titles.length; i++) {
          if (t === titles[i] || t.indexOf(titles[i]) === 0) {
            var c = h.closest('section, [class*="recommend"], [class*="reco"], #bottom-reco');
            if (c) hide(c);
            break;
          }
        }
      });
  }

  // 4) 搜索页（search.bilibili.com 等）：内容不动（含封面/播放量/时间/UP主），只清导航
  function clean() {
    cleanNav();
    var path = location.pathname || '/';
    if (path === '/' || path === '') cleanHome();
    if (/\/video\//.test(path)) cleanWatch();
  }

  clean();
  var timer = null;
  new MutationObserver(function () {
    if (timer) return;
    timer = setTimeout(function () { timer = null; clean(); }, 120);
  }).observe(document.documentElement, { childList: true, subtree: true });
})();