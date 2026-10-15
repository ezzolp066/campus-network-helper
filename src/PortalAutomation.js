// Executed inside the real portal page. Never returns credentials to the log.
(() => {
  const visible = e => !!e && !e.disabled && e.getClientRects().length > 0 &&
    getComputedStyle(e).visibility !== 'hidden' && getComputedStyle(e).display !== 'none';
  const normal = s => (s || '').replace(/\s+/g, '').toLowerCase();
  function inspect() {
    const inputs = [...document.querySelectorAll('input')].filter(visible);
    const passwords = inputs.filter(e => e.type === 'password');
    const text = inputs.filter(e => ['text', 'tel', 'email', 'number'].includes(e.type));
    const named = text.filter(e => /^(ddddd|user_account|username|userid|account|user|loginname)$/i.test(e.name) ||
      /^(ddddd|user_account|username|userid|account|user|loginname)$/i.test(e.id));
    const account = named.length === 1 ? named[0] : text.length === 1 ? text[0] : null;
    const candidates = [...document.querySelectorAll('button,input[type=submit],input[type=button],a,[role=button],div,span')]
      .filter(e => visible(e) && ['登录', '登陆', 'login', '登录上网', '连接网络'].includes(normal(e.value || e.textContent)));
    const leaf = candidates.filter(e => !candidates.some(other => other !== e && e.contains(other)));
    return { account, password: passwords.length === 1 ? passwords[0] : null,
      button: leaf.length === 1 ? leaf[0] : null, inputCount: inputs.length, buttonCount: leaf.length };
  }
  function state() {
    const comments = document.createTreeWalker(document, NodeFilter.SHOW_COMMENT);
    const states = new Set();
    while (comments.nextNode()) {
      const match = comments.currentNode.data.trim().match(/^Dr\.COM(?:1\.0)?WebLoginID_([023])\.htm$/);
      if (match) states.add(match[1]);
    }
    if (states.size !== 1) return 'Unknown';
    return ({'0': 'LoggedOut', '2': 'Failed', '3': 'LoggedIn'})[[...states][0]];
  }
  function errorText() {
    const specific = [...document.querySelectorAll('[role=alert],.layui-layer-content,.layer-content,.error,.error-message,.error-msg,.login-error,.alert-danger,#error,#errorMsg,#message,#msg')];
    const rejection = /密码错误|账号或密码|用户名或密码|帐号或密码|认证失败|登录失败|登陆失败|用户不存在|账号不存在|帐号不存在|已被停用|已停机|欠费|设备.{0,8}上限|终端.{0,8}上限|验证码.{0,8}错误|认证被拒绝/i;
    const leaves = [...document.querySelectorAll('p,span,div,td,li')].filter(e =>
      visible(e) && e.childElementCount === 0 && rejection.test(e.innerText || ''));
    for (const element of [...specific, ...leaves]) {
      if (!visible(element)) continue;
      const message = (element.innerText || '').replace(/\s+/g, ' ').trim();
      if (message && message.length <= 240) return message;
    }
    return '';
  }
  window.__campusAutomation = {
    status() {
      const fields = inspect();
      return { state: state(), ready: !!(fields.account && fields.password && fields.button),
        inputCount: fields.inputCount, buttonCount: fields.buttonCount,
        alert: window.__campusLastAlert || '', error: errorText(), host: location.hostname,
        fieldNames: [...document.querySelectorAll('input')].filter(visible)
          .map(e => ({type: e.type, name: e.name, id: e.id})) };
    },
    focusField(kind) {
      const fields = inspect();
      const element = kind === 'account' ? fields.account : kind === 'password' ? fields.password : null;
      if (!element) throw Error('LOGIN_FIELD_NOT_UNIQUE');
      element.focus();
      Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(element, '');
      element.dispatchEvent(new Event('input', {bubbles: true}));
      return document.activeElement === element;
    },
    checkFilled(user, password) {
      const fields = inspect();
      return !!fields.account && !!fields.password && fields.account.value === user && fields.password.value === password;
    },
    buttonPoint() {
      const fields = inspect();
      if (!fields.button) throw Error('LOGIN_BUTTON_NOT_UNIQUE');
      fields.button.scrollIntoView({ block: 'center' });
      const box = fields.button.getBoundingClientRect();
      if (box.width <= 0 || box.height <= 0) throw Error('LOGIN_BUTTON_NOT_VISIBLE');
      return {x: box.left + box.width / 2, y: box.top + box.height / 2};
    },
    fill(user, password) {
      const fields = inspect();
      if (!fields.account || !fields.password || !fields.button) throw Error('LOGIN_CONTROLS_NOT_UNIQUE');
      const setter = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set;
      for (const [element, value] of [[fields.account, user], [fields.password, password]]) {
        setter.call(element, value);
        element.dispatchEvent(new Event('input', { bubbles: true }));
        element.dispatchEvent(new Event('change', { bubbles: true }));
      }
      fields.button.scrollIntoView({ block: 'center' });
      const box = fields.button.getBoundingClientRect();
      if (box.width <= 0 || box.height <= 0) throw Error('LOGIN_BUTTON_NOT_VISIBLE');
      return { x: box.left + box.width / 2, y: box.top + box.height / 2 };
    }
  };
  if (!window.__campusAlertHooked) {
    window.alert = message => { window.__campusLastAlert = String(message); };
    window.__campusAlertHooked = true;
  }
  return window.__campusAutomation.status();
})()
