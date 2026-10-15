package com.ooglex.techleaders;

import android.app.Activity;
import android.content.ActivityNotFoundException;
import android.content.Intent;
import android.graphics.Bitmap;
import android.net.Uri;
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
 * 「科技领袖实时动态流」安卓应用：用系统 WebView 打开线上专栏。
 * 页面、数据与密码门都来自线上 ooglex.com，应用本身不存任何账号或密钥。
 */
public class MainActivity extends Activity {

    static final String HOME_URL = "https://www.ooglex.com/apps/tech-leaders/";

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
        s.setDomStorageEnabled(true);          // 页面用 sessionStorage/localStorage 缓存名录与动态
        s.setDatabaseEnabled(true);
        s.setLoadWithOverviewMode(true);
        s.setUseWideViewPort(true);
        s.setMediaPlaybackRequiresUserGesture(true);
        s.setAllowFileAccess(false);
        s.setAllowContentAccess(false);
        s.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        // 让网站能识别「在应用内打开」（例如隐藏「下载安卓 App」入口）
        s.setUserAgentString(s.getUserAgentString() + " OoglexApp/" + appVersion());

        // 密码门会话 Cookie 由 pro-api.ooglex.com 下发，WebView 默认不接受跨子域 Cookie，需要显式打开。
        CookieManager cookies = CookieManager.getInstance();
        cookies.setAcceptCookie(true);
        cookies.setAcceptThirdPartyCookies(webView, true);

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

    /** ooglex.com 站内链接留在应用内；X、新闻原文等外部链接交给系统浏览器或对应应用。 */
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
                + "<style>body{margin:0;min-height:100vh;display:grid;place-items:center;background:#fff1e5;color:#221f1b;"
                + "font-family:-apple-system,'PingFang SC','Microsoft YaHei',sans-serif;padding:24px;box-sizing:border-box}"
                + "main{max-width:360px;text-align:center}h1{font-size:20px;margin:0 0 8px}p{color:#6b625a;font-size:14px;line-height:1.6;margin:0 0 20px}"
                + "a{display:inline-block;min-width:160px;padding:12px 18px;border-radius:10px;background:#171717;color:#fff;text-decoration:none;font-weight:700}</style>"
                + "</head><body><main><h1>暂时无法连接 Ooglex</h1>"
                + "<p>请检查网络后重试。科技领袖动态需要联网读取。</p>"
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

    @Override
    protected void onPause() {
        super.onPause();
        CookieManager.getInstance().flush();
        if (webView != null) webView.onPause();
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (webView != null) webView.onResume();
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
