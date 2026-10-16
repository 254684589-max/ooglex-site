# 科技领袖安卓应用（OOGLE X）

## 用途
把「科技领袖实时动态流」（`/apps/tech-leaders/`）做成可下载安装的安卓应用，桌面名称为「OOGLE X」。应用是一个原生 WebView 外壳，打开 `https://www.ooglex.com/apps/tech-leaders/`：页面、数据、密码门都来自线上网站，网站更新后应用内容自动同步，无需重新安装。

- 源码：`android/tech-leaders/`（纯 Java + 系统 WebView，无第三方依赖，minSdk 24 / targetSdk 34）。
- 构建：`.github/workflows/android-tech-leaders.yml`。任何分支推送都会构建并上传为 Actions 产物；只有 `main` 会发布到 GitHub Release `tech-leaders-android`。
- 分发：Pages 部署时（`deploy_protected_pages.yml` 的 “Add latest Tech Leaders Android APK” 步骤）把 Release 中的 `ooglex-tech-leaders.apk` 与 `ooglex-tech-leaders.json` 复制到 `https://www.ooglex.com/apps/tech-leaders/app/`；下载页为同目录 `index.html`。
- 应用内：站内链接留在应用内；X 原帖、新闻原文等外部链接交给系统浏览器；User-Agent 追加 `OoglexApp/<版本>`，网站据此在应用内隐藏「安卓 App 下载」入口。
- 权限：仅 `INTERNET`、`ACCESS_NETWORK_STATE`。

## 签名（需要所有者操作）
未配置签名 Secrets 时，CI 使用调试签名：可以安装，但每次构建的签名不同，升级时需先卸载旧版。要启用固定的正式签名，所有者在自己电脑上生成密钥：

```
keytool -genkeypair -v -keystore ooglex-tech-leaders.jks -alias ooglex -keyalg RSA -keysize 2048 -validity 10000
base64 -i ooglex-tech-leaders.jks   # Windows 可用 certutil -encode
```

再在 GitHub 仓库 Settings → Secrets and variables → Actions 中新增：
`ANDROID_KEYSTORE_B64`（上面 base64 输出）、`ANDROID_KEYSTORE_PASSWORD`、`ANDROID_KEY_ALIAS`（如 `ooglex`）、`ANDROID_KEY_PASSWORD`。
密钥文件请自行妥善备份；丢失后已安装用户将无法直接升级。密钥绝不提交到仓库。

## 费用
无额外费用：使用 GitHub Actions 免费额度与现有 GitHub Pages；不上架应用商店。

## 已知限制
- 未上架应用商店，安装时手机会提示「未知来源」。
- iPhone 不能安装 APK；iPhone 用户可用 Safari「添加到主屏幕」。
- WebView 内「保存分享图片」（blob 下载）与系统分享面板不可用，页面会提示改用帖子链接。

## 删除方法 / 故障回退
删除 `android/tech-leaders/`、`.github/workflows/android-tech-leaders.yml`、`apps/tech-leaders/app/`、科技领袖页中的 `hero-app-link`，以及 `deploy_protected_pages.yml` 中的 APK 复制步骤；在 GitHub 删除 Release `tech-leaders-android`。Release 不存在或下载失败时，网站部署照常完成，下载页显示「安装包暂未发布」。

## 图标

桌面图标为原创设计：黑色背景、白色光晕圆环，中间是白色「OX」字母组合（`app/src/main/res/drawable/ic_launcher_foreground.xml`、`ic_launcher.xml`）。不使用 X（原推特）的商标标志，以免被误认为 X 官方应用；上架应用商店时也不会因商标被拒。
