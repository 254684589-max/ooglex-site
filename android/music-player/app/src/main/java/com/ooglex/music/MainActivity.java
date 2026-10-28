package com.ooglex.music;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.webkit.CookieManager;
import android.webkit.WebChromeClient;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.widget.FrameLayout;
import android.widget.ProgressBar;

/**
 * 「流光播放器」安卓应用：用系统 WebView 打开线上播放器页。
 * 页面、曲目与全球曲库都来自线上 ooglex.com，应用本身不存任何账号、密钥或音频。
 * 与 android/tech-leaders 同一套外壳；区别是切到后台不暂停 WebView，息屏后音乐继续播放。
 */
public class MainActivity extends Activity {

    static final String HOME_URL = "https://www.ooglex.com/apps/music-player/";

    private WebView webView;
    private ProgressBar progress;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        FrameLayout root = new FrameLayout(this);
        root.setFitsSystemWindows(true);

        webView = new WebView(this);
        root.addView(webView, new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        progress = new ProgressBar(this, null, android.R.attr.progressBarStyleHorizontal);
        progress.setMax(100);
        FrameLayout.LayoutParams barParams = new FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(3));
        root.addView(progress, barParams);

        setContentView(root);

        WebSettings s = webView.getSettings();
        s.setJavaScriptEnabled(true);
        s.setDomStorageEnabled(true);          // 页面用 localStorage 记住循环、随机与主题
        s.setDatabaseEnabled(true);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        // 一首播完自动接下一首、息屏连播都不经过点击；要求手势会让 WebView 拦下这些播放。
        // 首次出声仍由页面上的播放键触发，页面本身从不自动播放。
        s.setMediaPlaybackRequiresUserGesture(false);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        // 让网站能识别「在应用内打开」（例如隐藏「下载安卓 App」入口）
        s.setUserAgentString(s.getUserAgentString() + " OoglexApp/" + appVersion());

        CookieManager.getInstance().setAcceptCookie(true);

        webView.setWebChromeClient(new WebChromeClient() {
            @Override
            public void onProgressChanged(WebView view, int newProgress) {
                progress.setProgress(newProgress);
                progress.setVisibility(newProgress >= 100 ? View.GONE : View.VISIBLE);
            }
        });

        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                return handleExternal(request.getUrl());
            }

            // Android 5.1–6.0（API 22/23）只调用这个旧版本。
            @Override
            @SuppressWarnings("deprecation")
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                return url != null && handleExternal(Uri.parse(url));
            }

            @Override
            public void onPageStarted(WebView view, String url, Bitmap favicon) {
                progress.setVisibility(View.VISIBLE);
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                CookieManager.getInstance().flush();
            }

            @Override
            public void onReceivedError(WebView view, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) showOfflinePage();
            }

            // Android 5.1（API 22）只调用这个旧版本；它只报主页面的错误。
            @Override
            @SuppressWarnings("deprecation")
            public void onReceivedError(WebView view, int errorCode, String description, String failingUrl) {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) showOfflinePage();
            }
        });

        // 页面里的普通文件下载交给系统浏览器处理（blob: 生成的图片在 WebView 内无法保存）。
        webView.setDownloadListener((url, userAgent, contentDisposition, mimeType, contentLength) -> {
            if (url != null && (url.startsWith("https://") || url.startsWith("http://"))) {
                openInBrowser(Uri.parse(url));
            }
        });

        if (savedInstanceState != null) {
            webView.restoreState(savedInstanceState);
        } else {
            webView.loadUrl(startUrl(getIntent()));
        }
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        String url = startUrl(intent);
        if (intent != null && intent.getData() != null) webView.loadUrl(url);
    }

    private String startUrl(Intent intent) {
        if (intent != null && intent.getData() != null && isOoglex(intent.getData())) {
            return intent.getData().toString();
        }
        return HOME_URL;
    }

    private static boolean isOoglex(Uri uri) {
        String host = uri.getHost();
        if (host == null) return false;
        host = host.toLowerCase();
        return "https".equalsIgnoreCase(uri.getScheme())
                && (host.equals("ooglex.com") || host.endsWith(".ooglex.com"));
    }

    /** ooglex.com 站内链接留在应用内；Jamendo 曲目页、许可文本等外部链接交给系统浏览器。 */
    private boolean handleExternal(Uri uri) {
        if (isOoglex(uri)) return false;
        String scheme = uri.getScheme();
        if ("about".equals(scheme) || "data".equals(scheme) || "blob".equals(scheme) || "javascript".equals(scheme)) {
            return false;
        }
        openInBrowser(uri);
        return true;
    }

    private void openInBrowser(Uri uri) {
        try {
            startActivity(new Intent(Intent.ACTION_VIEW, uri));
        } catch (ActivityNotFoundException ignored) {
            // 手机上没有可以打开该链接的应用时静默忽略。
        }
    }

    private void showOfflinePage() {
        String html = "<!doctype html><html lang='zh-CN'><head><meta charset='utf-8'>"
                + "<meta name='viewport' content='width=device-width,initial-scale=1'>"
                + "<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#07141c;color:#f3f6f8;"
                + "font-family:-apple-system,'PingFang SC','Microsoft YaHei',sans-serif;padding:24px;box-sizing:border-box}"
                + "main{max-width:360px;text-align:center}h1{font-size:20px;margin:0 0 8px}p{color:#94a5b2;font-size:14px;line-height:1.6;margin:0 0 20px}"
                + "a{display:inline-block;min-width:160px;padding:12px 18px;border-radius:999px;background:#e0c36a;color:#1c1608;text-decoration:none;font-weight:700}</style>"
                + "</head><body><main><h1>暂时无法连接 Ooglex</h1>"
                + "<p>请检查网络后重试。播放器和曲目都需要联网读取。</p>"
                + "<a href='" + HOME_URL + "'>重新加载</a></main></body></html>";
        webView.loadDataWithBaseURL(HOME_URL, html, "text/html", "utf-8", HOME_URL);
    }

    @Override
    public void onBackPressed() {
        if (webView != null && webView.canGoBack()) {
            webView.goBack();
        } else {
            super.onBackPressed();
        }
    }

    @Override
    protected void onSaveInstanceState(Bundle outState) {
        super.onSaveInstanceState(outState);
        if (webView != null) webView.saveState(outState);
    }

    // 不调用 webView.onPause()：那会暂停页面里的音频，切到后台或息屏时音乐就停了。
    @Override
    protected void onPause() {
        super.onPause();
        CookieManager.getInstance().flush();
    }

    @Override
    protected void onDestroy() {
        if (webView != null) {
            webView.stopLoading();
            webView.destroy();
            webView = null;
        }
        super.onDestroy();
    }

    private String appVersion() {
        try {
            return getPackageManager().getPackageInfo(getPackageName(), 0).versionName;
        } catch (Exception e) {
            return "1";
        }
    }

    private int dp(int value) {
        return Math.round(value * getResources().getDisplayMetrics().density);
    }
}
