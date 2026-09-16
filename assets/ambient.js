/* Ooglex 全站背景音乐控件已移除。
   保留此兼容文件，是因为部分旧页面仍引用 assets/ambient.js。
   页面加载时只清理遗留的 #music-toggle，不再注入按钮，也不再创建音频。 */
(function () {
  function removeLegacyMusicControl() {
    var nodes = document.querySelectorAll('#music-toggle');
    for (var i = 0; i < nodes.length; i++) nodes[i].remove();
  }
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', removeLegacyMusicControl);
  } else {
    removeLegacyMusicControl();
  }
})();
