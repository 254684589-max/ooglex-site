const cfg = window.OOGLEX_AUTH_CONFIG || {};
const $ = (id) => document.getElementById(id);
const states = [
  $('setup-state'),
  $('guest-state'),
  $('recovery-state'),
  $('recovery-error-state'),
  $('user-state')
].filter(Boolean);
const msg = $('message');

function show(state) {
  states.forEach((s) => s.classList.add('hidden'));
  if (state) state.classList.remove('hidden');
}

function say(text, kind = '') {
  msg.textContent = text || '';
  msg.className = 'message' + (kind ? ' ' + kind : '');
}

function isEnglish() {
  try {
    return document.documentElement.getAttribute('data-lang') === 'en' ||
      localStorage.getItem('ooglex.language') === 'en';
  } catch (_) {
    return false;
  }
}

function tr(zh, en) {
  return isEnglish() ? en : zh;
}

function protectFromTranslation(element) {
  if (!element) return;
  element.setAttribute('translate', 'no');
  element.classList.add('notranslate');
}

function syncDocumentLanguage() {
  const en = isEnglish();
  document.documentElement.lang = en ? 'en' : 'zh-CN';
  document.documentElement.setAttribute('data-lang', en ? 'en' : 'zh');
}

function tab(login) {
  $('tab-login').classList.toggle('active', login);
  $('tab-signup').classList.toggle('active', !login);
  $('login-form').classList.toggle('hidden', !login);
  $('signup-form').classList.toggle('hidden', login);
  say('');
}

function readAuthUrlState() {
  const query = new URLSearchParams(location.search || '');
  const hash = new URLSearchParams((location.hash || '').replace(/^#/, ''));
  const pick = (key) => query.get(key) || hash.get(key) || '';
  const code = pick('error_code');
  const description = pick('error_description');
  const type = pick('type');
  return {
    code,
    description,
    recovery: type === 'recovery',
    hasError: Boolean(code || description || pick('error'))
  };
}

function cleanAuthUrl() {
  try {
    history.replaceState({}, document.title, location.pathname);
  } catch (_) {}
}

function friendlyAuthError(state) {
  if (state.code === 'otp_expired') {
    return tr(
      '此密码重置链接已失效或已被使用，请重新申请一封新的重置邮件。',
      'This password-reset link has expired or has already been used. Please request a new reset email.'
    );
  }
  if (state.description) {
    const text = state.description.replace(/\+/g, ' ');
    return tr('验证链接无法使用：' + text, 'The verification link could not be used: ' + text);
  }
  return tr(
    '验证链接无法使用，请重新申请一封新的重置邮件。',
    'The verification link could not be used. Please request a new reset email.'
  );
}

function friendlyError(error) {
  const text = error?.message || String(error || '');
  if (/email rate limit exceeded/i.test(text)) {
    return tr('邮件发送过于频繁，请稍后再试。', 'Too many emails were requested. Please try again later.');
  }
  return text;
}

function applyRecoveryCopy() {
  const en = isEnglish();
  const pairs = {
    'recovery-error-badge': ['链接失效', 'Link expired'],
    'recovery-error-title': ['重置链接已失效', 'Reset link expired'],
    'recovery-error-help': ['重新申请后，请只使用最新收到的重置邮件。', 'Request a new email and use only the newest reset message.'],
    'retry-email-label': ['邮箱', 'Email'],
    'retry-recovery-submit': ['重新发送重置邮件', 'Send a new reset email'],
    'back-account-button': ['返回账户中心 / 登录', 'Back to account / sign in']
  };
  Object.entries(pairs).forEach(([id, copy]) => {
    const el = $(id);
    if (el) el.textContent = en ? copy[1] : copy[0];
  });
}

syncDocumentLanguage();
['user-email', 'user-name', 'user-plan', 'user-status'].forEach((id) => protectFromTranslation($(id)));
$('tab-login').onclick = () => tab(true);
$('tab-signup').onclick = () => tab(false);
applyRecoveryCopy();

if (!cfg.enabled || !cfg.supabaseUrl || !cfg.supabasePublishableKey) {
  show($('setup-state'));
} else {
  boot();
}

async function boot() {
  try {
    const { createClient } = await import('https://esm.sh/@supabase/supabase-js@2');
    const urlState = readAuthUrlState();
    let authError = urlState.hasError ? urlState : null;
    let recoveryMode = urlState.recovery;

    const sb = createClient(cfg.supabaseUrl, cfg.supabasePublishableKey, {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true
      }
    });

    async function render(user) {
      if (!user) {
        show($('guest-state'));
        return;
      }
      let profile = null;
      try {
        const result = await sb
          .from('profiles')
          .select('display_name,plan,status')
          .eq('id', user.id)
          .maybeSingle();
        if (!result.error) profile = result.data;
      } catch (_) {}

      const emailEl = $('user-email');
      const nameEl = $('user-name');
      const planEl = $('user-plan');
      const statusEl = $('user-status');
      [emailEl, nameEl, planEl, statusEl].forEach(protectFromTranslation);

      emailEl.textContent = user.email || '—';
      nameEl.textContent = profile?.display_name || user.user_metadata?.display_name || tr('未设置', 'Not set');
      planEl.textContent = String(profile?.plan || 'free').toUpperCase();
      statusEl.textContent = String(profile?.status || 'active').toUpperCase();
      show($('user-state'));
    }

    async function sendRecovery(email) {
      const result = await sb.auth.resetPasswordForEmail(email, {
        redirectTo: cfg.redirectUrl
      });
      if (result.error) {
        say(friendlyError(result.error), 'error');
        return false;
      }
      say(
        tr('如果该邮箱已注册，你会收到一封新的重置邮件。', 'If that email is registered, a new reset email will be sent.'),
        'ok'
      );
      return true;
    }

    // Register the listener before reading the initial session so PASSWORD_RECOVERY
    // cannot be missed while Supabase processes the callback URL.
    sb.auth.onAuthStateChange(async (event, session) => {
      if (event === 'PASSWORD_RECOVERY') {
        authError = null;
        recoveryMode = true;
        say('');
        show($('recovery-state'));
        return;
      }
      if (authError || recoveryMode) return;
      if (event === 'SIGNED_OUT') {
        show($('guest-state'));
        return;
      }
      if (session?.user) await render(session.user);
    });

    const initial = await sb.auth.getSession();
    const initialUser = initial.data.session?.user || null;

    if (authError) {
      $('retry-recovery-email').value = initialUser?.email || '';
      show($('recovery-error-state'));
      say(friendlyAuthError(authError), 'error');
    } else if (recoveryMode) {
      show($('recovery-state'));
    } else {
      await render(initialUser);
    }

    $('login-form').onsubmit = async (event) => {
      event.preventDefault();
      say(tr('正在登录…', 'Signing in…'));
      const result = await sb.auth.signInWithPassword({
        email: $('login-email').value.trim(),
        password: $('login-password').value
      });
      if (result.error) return say(friendlyError(result.error), 'error');
      say(tr('登录成功。', 'Signed in.'), 'ok');
    };

    $('signup-form').onsubmit = async (event) => {
      event.preventDefault();
      say(tr('正在创建账户…', 'Creating account…'));
      const result = await sb.auth.signUp({
        email: $('signup-email').value.trim(),
        password: $('signup-password').value,
        options: {
          emailRedirectTo: cfg.redirectUrl,
          data: { display_name: $('signup-name').value.trim() }
        }
      });
      if (result.error) return say(friendlyError(result.error), 'error');
      say(
        result.data.session
          ? tr('注册成功并已登录。', 'Account created and signed in.')
          : tr('注册成功，请查收验证邮件。', 'Account created. Check your email to confirm it.'),
        'ok'
      );
    };

    $('forgot-button').onclick = async () => {
      const email = $('login-email').value.trim();
      if (!email) return say(tr('请先输入邮箱。', 'Enter your email first.'), 'error');
      await sendRecovery(email);
    };

    $('retry-recovery-form').onsubmit = async (event) => {
      event.preventDefault();
      const email = $('retry-recovery-email').value.trim();
      if (!email) return say(tr('请先输入邮箱。', 'Enter your email first.'), 'error');
      await sendRecovery(email);
    };

    $('back-account-button').onclick = async () => {
      authError = null;
      recoveryMode = false;
      cleanAuthUrl();
      say('');
      const current = await sb.auth.getSession();
      await render(current.data.session?.user || null);
    };

    $('recovery-form').onsubmit = async (event) => {
      event.preventDefault();
      const result = await sb.auth.updateUser({
        password: $('recovery-password').value
      });
      if (result.error) return say(friendlyError(result.error), 'error');
      recoveryMode = false;
      cleanAuthUrl();
      say(tr('密码已更新。', 'Password updated.'), 'ok');
      const userResult = await sb.auth.getUser();
      await render(userResult.data.user);
    };

    $('logout-button').onclick = async () => {
      const result = await sb.auth.signOut();
      if (result.error) say(friendlyError(result.error), 'error');
    };
  } catch (error) {
    show($('setup-state'));
    say(tr('账户模块加载失败：', 'Account module failed to load: ') + error.message, 'error');
  }
}
