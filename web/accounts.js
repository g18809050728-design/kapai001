'use strict';

(() => {
    const statuses = {
        account_changed: '登录已在另一处变更。请重新登录。',
        account_busy: '此浏览器已有标签页正在使用这个账号。',
        finish_current_run: '当前冒险尚未保存。请完成当前选择或重试保存。',
        invalid_credentials: '用户名、邮箱或密码有误，请重试。',
        email_unverified: '请打开注册验证邮件中的链接，激活账号后再登录。',
        username_invalid: '用户名需为 3–24 位字母、数字或下划线，首位为字母或数字。',
        username_taken: '这个用户名已被占用，请换一个。',
        username_already_set: '此账号已设置用户名。请重新打开账号面板。',
        password_mismatch: '两次输入的密码不一致。',
        invalid_token: '链接已过期或已使用。',
        rate_limited: '操作太频繁，请稍后再试。',
        mail_unavailable: '暂时无法发送邮件，请稍后重试。',
        save_conflict: '两台设备上的进度不同，请选择继续哪一份。',
        invalid_input: '请检查各项输入后重试。',
        email_invalid: '请输入有效的邮箱地址。',
        login_required: '登录已过期，请重新登录。',
        admin_required: '此功能需要管理员权限。',
        result_conflict: '该局已有不同结算，请核对本地对局。',
        database_unavailable: '账号服务暂时不可用，本机进度仍可保存。',
    };
    const playerNames = { P01: '林序', P02: '许知微', P03: '沈见章', P04: '唐以宁' };
    const difficultyNames = { relaxed: '轻松', normal: '标准', hard: '困难' };
    const results = { won: '胜利', lost: '失败', abandoned: '已放弃' };
    const slots = ['current_run', 'profile'];
    const prefix = 'kapai-account:';
    const guestChoice = prefix + 'guest-selected';
    const api = '/api/v1';
    const buildVersion = '__KAPAI_BUILD_VERSION__';
    let flags = {};
    let game;
    let reply;
    let account;
    let visible = false;
    let closed = true;
    let active = false;
    let menuState = 'checking';
    let guestSelected = false;
    let connecting = false;
    let exited = false;
    let releaseLock;
    let status = '';
    let showing = '';
    let uploadTimer;
    let uploadSince = 0;
    let uploadBusy = false;
    let pullBusy = false;
    let eventBusy = false;
    let needsUpload = false;
    const conflicts = new Map();

    try { guestSelected = sessionStorage.getItem(guestChoice) === 'true'; }
    catch { /* Guest play still works in this page when tab storage is unavailable. */ }

    function storageGet(key, fallback) {
        try { return JSON.parse(localStorage.getItem(prefix + key)) ?? fallback; }
        catch { return fallback; }
    }

    function storageSet(key, value) {
        try {
            if (value === undefined) localStorage.removeItem(prefix + key);
            else localStorage.setItem(prefix + key, JSON.stringify(value));
            return true;
        } catch {
            setStatus('浏览器无法保存同步状态。');
            return false;
        }
    }

    async function request(path, method = 'GET', data = undefined, userId = account?.user_id) {
        const headers = {};
        if (userId) headers['X-Kapai-Account'] = userId;
        if (method !== 'GET') headers['Content-Type'] = 'application/json';
        const result = await fetch(api + path, {
            method, headers, body: method === 'GET' ? undefined : JSON.stringify(data ?? {}),
            cache: 'no-store', credentials: 'same-origin', signal: AbortSignal.timeout(12000),
        });
        const response = await result.json();
        if (!result.ok) throw Object.assign(new Error(response.detail), { response, status: result.status });
        return response;
    }

    function element(name, text, parent) {
        const node = document.createElement(name);
        if (text) node.textContent = text;
        if (parent) parent.append(node);
        return node;
    }

    function button(text, parent, onClick) {
        const node = element('button', text, parent);
        node.type = 'button';
        node.addEventListener('click', () => {
            if (node.closest('#account-panel') && dialog.dataset.busy) return;
            void perform(onClick);
        });
        return node;
    }

    const dialog = element('dialog', '', document.body);
    dialog.id = 'account-panel';
    dialog.setAttribute('aria-labelledby', 'account-title');
    const cover = element('div', '', dialog);
    cover.className = 'account-cover';
    cover.setAttribute('aria-hidden', 'true');
    element('span', '交大四年', cover);
    element('strong', 'DDL 战争', cover);
    const content = element('section', '', dialog);
    content.className = 'account-content';
    const closeButton = button('×', content, closePanel);
    closeButton.className = 'account-close';
    closeButton.setAttribute('aria-label', '关闭');
    const title = element('h2', '', content);
    title.id = 'account-title';
    title.tabIndex = -1;
    const body = element('div', '', content);
    const notice = element('p', '', content);
    notice.setAttribute('role', 'status');
    const authPanels = ['login', 'register', 'check-mail', 'forgot', 'verify', 'legacy-password', 'reset', 'verified'];
    const viewport = window.visualViewport;
    const fitDialog = () => {
        dialog.style.setProperty('--account-viewport', (viewport?.height ?? innerHeight) + 'px');
        dialog.style.setProperty('--account-viewport-top', (viewport?.offsetTop ?? 0) + 'px');
    };
    viewport?.addEventListener('resize', fitDialog);
    viewport?.addEventListener('scroll', fitDialog);
    dialog.addEventListener('cancel', event => {
        if (dialog.dataset.busy) event.preventDefault();
    });
    dialog.addEventListener('keydown', event => event.stopPropagation());
    dialog.addEventListener('keyup', event => event.stopPropagation());
    dialog.addEventListener('close', () => {
        if (!dialog.open) {
            showing = '';
            document.getElementById('canvas')?.focus({ preventScroll: true });
        }
    });

    function closePanel() {
        if (!dialog.dataset.busy) dialog.close();
    }

    function setStatus(message) {
        status = message;
        if (dialog.open && !authPanels.includes(showing) && showing !== 'privacy') notice.textContent = message;
    }

    async function perform(action) {
        try { await action(); }
        catch (error) { setStatus(statuses[error.message] || '操作失败，请稍后重试。'); }
    }

    function startPanel(name, heading, description = '') {
        showing = name;
        dialog.dataset.panel = name;
        dialog.dataset.view = authPanels.includes(name) ? 'auth' : 'account';
        title.textContent = heading;
        body.replaceChildren();
        if (description) element('p', description, body).className = 'account-intro';
        notice.textContent = name === 'home' || name === 'saves' ? status : '';
        fitDialog();
        if (!dialog.open) dialog.showModal();
        content.scrollTop = 0;
        title.focus({ preventScroll: true });
    }

    function field(form, label, key, type = 'text', value = '') {
        const group = element('div', '', form);
        group.className = 'account-field';
        const caption = element('label', label, group);
        const input = element('input', '', group);
        input.id = 'account-field-' + key;
        caption.htmlFor = input.id;
        input.name = key;
        input.type = type;
        input.value = value;
        input.required = true;
        return input;
    }

    function hint(input, text) {
        const note = element('small', text, input.closest('.account-field'));
        note.id = input.id + '-hint';
        input.setAttribute('aria-describedby', note.id);
    }

    function usernameField(form) {
        const input = field(form, '用户名', 'username');
        input.autocomplete = 'username';
        input.minLength = 3;
        input.maxLength = 24;
        input.pattern = '[A-Za-z0-9][A-Za-z0-9_]{2,23}';
        input.autocapitalize = 'none';
        input.spellcheck = false;
        hint(input, statuses.username_invalid);
        return input;
    }

    function passwordField(form, label, name, isNew = false) {
        const input = field(form, label, name, 'password');
        input.autocomplete = isNew ? 'new-password' : 'current-password';
        input.autocapitalize = 'none';
        input.spellcheck = false;
        input.maxLength = 128;
        if (isNew) input.minLength = 12;
        const wrap = element('div', '');
        wrap.className = 'account-password';
        input.before(wrap);
        wrap.append(input);
        const toggle = button('显示', wrap, () => {
            const reveal = input.type === 'password';
            input.type = reveal ? 'text' : 'password';
            toggle.textContent = reveal ? '隐藏' : '显示';
            toggle.setAttribute('aria-label', (reveal ? '隐藏' : '显示') + label);
        });
        toggle.setAttribute('aria-controls', input.id);
        toggle.setAttribute('aria-label', '显示' + label);
        return input;
    }

    function formSubmit(form, label, handler) {
        const feedback = element('p', '', form);
        feedback.className = 'account-form-error';
        feedback.setAttribute('role', 'alert');
        const submit = element('button', label, form);
        submit.type = 'submit';
        submit.className = 'account-primary';
        form.addEventListener('input', () => { feedback.textContent = ''; });
        form.addEventListener('submit', async event => {
            event.preventDefault();
            if (dialog.dataset.busy) return;
            feedback.textContent = '';
            dialog.dataset.busy = 'true';
            form.setAttribute('aria-busy', 'true');
            closeButton.disabled = true;
            submit.disabled = true;
            try {
                await handler(Object.fromEntries(new FormData(form)));
            } catch (error) {
                feedback.textContent = statuses[error.message] || '操作失败，请稍后重试。';
            } finally {
                submit.disabled = false;
                closeButton.disabled = false;
                form.removeAttribute('aria-busy');
                delete dialog.dataset.busy;
            }
        });
    }

    function textButton(text, parent, action) {
        const node = button(text, parent, action);
        node.className = 'account-link';
        return node;
    }

    function alternate(text, label, action) {
        const row = element('div', '', body);
        row.className = 'account-alternate';
        if (text) element('span', text, row);
        textButton(label, row, action);
    }

    async function withAccountLock(id) {
        if (!navigator.locks) return true;
        return new Promise(resolve => {
            navigator.locks.request('kapai-account-' + id, { ifAvailable: true }, lock => {
                if (!lock) { resolve(false); return; }
                return new Promise(release => {
                    releaseLock = release;
                    resolve(true);
                });
            }).catch(() => resolve(false));
        });
    }

    async function attach(user) {
        if (user?.user_id === account?.user_id) {
            account = user;
            return true;
        }
        if (!closed) return false;
        releaseLock?.();
        releaseLock = undefined;
        if (user && !await withAccountLock(user.user_id)) {
            setStatus('此浏览器已有标签页正在使用这个账号。');
            return false;
        }
        if (game('switch', user?.user_id || '') !== true) {
            releaseLock?.();
            releaseLock = undefined;
            return false;
        }
        account = user;
        clearTimeout(uploadTimer);
        needsUpload = false;
        uploadSince = 0;
        conflicts.clear();
        setStatus('');
        return true;
    }

    async function readAccount() {
        return (await request('/auth/session', 'GET', undefined, '')).user;
    }

    function publishMenu(state, message = '') {
        menuState = state;
        game('account_menu', state, String(flags.registration === true), account?.nickname || '', message, account?.role || '');
    }

    function selectGuest(selected) {
        guestSelected = selected;
        try {
            if (selected) sessionStorage.setItem(guestChoice, 'true');
            else sessionStorage.removeItem(guestChoice);
        } catch { /* Keep the current page usable. */ }
    }

    async function enterGuest() {
        if (!['login', 'unavailable'].includes(menuState)) return;
        if (account && !closed && game('close_run', '') !== true) {
            publishMenu(menuState, statuses.finish_current_run);
            return;
        }
        if (!await attach(null)) return;
        selectGuest(true);
        publishMenu('guest');
    }

    function exitGuest() {
        if (menuState !== 'guest') return false;
        if (!closed && game('close_run', '') !== true) {
            publishMenu('guest', '当前冒险尚未保存。请继续冒险并保存进度后重试。');
            return false;
        }
        selectGuest(false);
        publishMenu(active ? 'login' : 'unavailable');
        return true;
    }

    async function finishSignIn(expected) {
        const user = await readAccount();
        if (user?.user_id !== expected.user_id) throw new Error('login_required');
        if (account?.user_id !== user.user_id && !closed && game('close_run', '') !== true) {
            throw new Error('finish_current_run');
        }
        if (!await attach(user)) throw new Error('account_busy');
        selectGuest(false);
        await syncFromCloud();
        publishMenu('ready');
        dialog.close();
        void flushEvents();
    }

    function showPrivacy() {
        startPanel('privacy', '隐私设置');
        const label = element('label', '', body);
        label.className = 'account-checkbox';
        const input = element('input', '', label);
        input.type = 'checkbox';
        input.checked = storageGet('visitor-opt-in', false);
        label.append('参与匿名访客统计');
        const note = element('p', '启用后，未使用账号登录时访问主菜单会发送此浏览器的随机标识。账号对局用于个人历史和试玩统计。', body);
        note.id = 'account-privacy-description';
        input.setAttribute('aria-describedby', note.id);
        const feedback = element('p', '', body);
        feedback.setAttribute('role', 'status');
        input.addEventListener('change', () => {
            if (!storageSet('visitor-opt-in', input.checked)) {
                input.checked = storageGet('visitor-opt-in', false);
                feedback.textContent = '此浏览器无法保存隐私设置。';
                return;
            }
            feedback.textContent = input.checked ? '已启用。' : '已关闭。';
            if (input.checked) void visitor().catch(() => {});
        });
    }

    async function visitor() {
        if (account || !storageGet('visitor-opt-in', false)) return;
        const id = storageGet('visitor', crypto.randomUUID());
        if (!storageSet('visitor', id)) return;
        await request('/events', 'POST', { event_type: 'menu_opened', visitor_id: id, event_id: crypto.randomUUID() });
    }

    function requireClosed(heading, next, returnTo = 'menu') {
        if (closed) { void perform(next); return; }
        startPanel('close-run', heading, '当前冒险需要先保存并返回主菜单。');
        const actions = element('form', '', body);
        actions.className = 'account-confirm-actions';
        button('取消', actions, closePanel);
        formSubmit(actions, '保存并继续', () => {
            if (game('close_run', returnTo) !== true) throw new Error('finish_current_run');
            return next();
        });
    }

    function showPanel() {
        if (menuState === 'guest') {
            startPanel('home', '游客身份', '进度保存在此浏览器，重新选择游客后可继续。');
        } else {
            if (menuState !== 'ready' || !account) { showLogin(); return; }
            startPanel('home', '账号', '已登录');
            const identity = element('div', '', body);
            identity.className = 'account-identity';
            element('strong', account.nickname, identity);
            element('p', account.role === 'admin' ? '管理员' : '玩家', identity);
            if (account.username) element('small', '用户名 · ' + account.username, identity);
            if (!account.username) button('设置登录用户名', body, showUsername);
        }
        const actions = element('div', '', body);
        actions.className = 'account-actions';
        button('退出登录', actions, showLogout);
        if (account) {
            const footer = element('div', '', body);
            footer.className = 'account-alternate';
            textButton('删除账号', footer, () => requireClosed('删除账号', showDelete));
        }
    }

    function showLogout() {
        if (menuState !== 'guest' && (!account || menuState !== 'ready')) return;
        const guest = menuState === 'guest';
        startPanel('logout', '退出登录？', guest
            ? '将返回身份选择。本机游客存档会保留。'
            : '将返回身份选择。此账号的本机存档会保留，再次登录后可继续。');
        if (!closed) element('p', '当前冒险会先保存；保存失败时会保留登录状态。', body);
        if (!guest && (needsUpload || uploadBusy || conflicts.size))
            element('p', '仍有待同步或待处理的云存档。本机副本会保留，请稍后用此账号继续同步。', body);
        const form = element('form', '', body);
        form.className = 'account-confirm-actions';
        button('取消', form, showPanel);
        formSubmit(form, !closed ? '保存并退出登录' : '退出登录', async () => {
            if (guest) {
                if (!exitGuest()) throw new Error('finish_current_run');
            } else {
                if (!closed && game('close_run', '') !== true) throw new Error('finish_current_run');
                await flushEvents();
                await flushSaves();
                await request('/auth/logout', 'POST');
                if (!await attach(null)) throw new Error('finish_current_run');
                selectGuest(false);
                publishMenu('login');
            }
            dialog.close();
        });
    }

    function showLogin(identifier = '') {
        startPanel('login', '登录', flags.cloud ? '登录后可在其他设备继续冒险。' : '');
        const form = element('form', '', body);
        const identity = field(form, '用户名或邮箱', 'identifier', 'text', identifier);
        identity.autocomplete = 'username';
        identity.autocapitalize = 'none';
        identity.spellcheck = false;
        identity.maxLength = 254;
        const password = passwordField(form, '密码', 'password');
        if (flags.reset) {
            const recovery = textButton('忘记密码？', password.closest('.account-field'),
                () => showForgot(identity.value.includes('@') ? identity.value : ''));
            recovery.classList.add('account-recovery');
        }
        formSubmit(form, '登录', async values => {
            const user = await request('/auth/login', 'POST', { ...values, identifier: values.identifier.trim() }, '');
            password.value = '';
            await finishSignIn(user);
        });
        if (flags.registration) alternate('还没有账号？', '创建账号', showRegister);
    }

    function showRegister() {
        startPanel('register', '创建账号');
        const form = element('form', '', body);
        usernameField(form);
        const password = passwordField(form, '密码', 'password', true);
        hint(password, '使用 12–128 个字符。');
        passwordField(form, '确认密码', 'confirmation', true);
        formSubmit(form, '注册', async values => {
            if (values.password !== values.confirmation) throw new Error('password_mismatch');
            const { username, password } = values;
            const user = await request('/auth/register', 'POST', { username, password }, '');
            await finishSignIn(user);
        });
        alternate('已有账号？', '返回登录', () => showLogin());
    }

    function emailField(form, value = '') {
        const input = field(form, '邮箱', 'email', 'email', value);
        input.autocomplete = 'email';
        input.maxLength = 254;
        input.spellcheck = false;
        return input;
    }

    function showForgot(email = '') {
        startPanel('forgot', '找回密码', '已有验证邮箱的账号可通过邮件重置密码。');
        const form = element('form', '', body);
        emailField(form, email);
        formSubmit(form, '发送重置链接', async values => {
            await request('/auth/forgot', 'POST', values, '');
            startPanel('check-mail', '查收邮件', '如果该邮箱已验证，请打开邮件中的链接重置密码。');
            alternate('', '返回登录', () => showLogin(values.email));
        });
        alternate('', '返回登录', () => showLogin(email));
    }

    function showToken(kind, token) {
        if (kind === 'reset') {
            showNewPassword(kind, token);
            return;
        }
        startPanel('verify', '验证邮箱', '请确认这是你亲自注册的账号。');
        const form = element('form', '', body);
        formSubmit(form, '验证邮箱', async () => {
            try {
                await request('/auth/verify', 'POST', { token }, '');
            } catch (error) {
                if (error.message !== 'password_setup_required') throw error;
                showNewPassword('verify', token);
                return;
            }
            showAuthComplete('邮箱已验证', '请使用注册时设置的密码登录。');
        });
        alternate('', '返回登录', () => showLogin());
    }

    function showAuthComplete(heading, description) {
        startPanel('verified', heading, description);
        button('前往登录', body, () => showLogin()).className = 'account-primary';
    }

    function showNewPassword(kind, token) {
        const legacy = kind === 'verify';
        startPanel(legacy ? 'legacy-password' : 'reset', legacy ? '设置账号密码' : '重置密码');
        const form = element('form', '', body);
        hint(passwordField(form, '新密码', 'password', true), '使用 12–128 个字符。');
        passwordField(form, '确认密码', 'confirmation', true);
        formSubmit(form, '保存密码', async values => {
            if (values.password !== values.confirmation) throw new Error('password_mismatch');
            await request('/auth/' + kind, 'POST', { token, password: values.password }, '');
            showAuthComplete(legacy ? '邮箱已验证' : '密码已重置', '请使用新密码登录。');
        });
        alternate('', '返回登录', () => showLogin());
    }

    function showUsername() {
        startPanel('username', '设置登录用户名', '设置后可用用户名或原邮箱登录。用户名只能设置一次。');
        const form = element('form', '', body);
        usernameField(form);
        formSubmit(form, '保存用户名', async values => {
            const user = await request('/me/username', 'POST', values);
            await attach(user);
            publishMenu('ready');
            showPanel();
        });
        alternate('', '返回账号', showPanel);
    }

    function showDelete() {
        startPanel('delete', '删除账号和云端数据');
        element('p', '删除账号会清除该账号的云存档和对局记录。请输入密码确认。', body);
        const form = element('form', '', body);
        passwordField(form, '密码', 'password');
        formSubmit(form, '确认删除账号', async values => {
            const id = account.user_id;
            await request('/me', 'DELETE', values);
            if (game('erase', id) !== true) setStatus('云端账号已删除，本机副本需要清理站点数据。');
            else setStatus('账号已删除。');
            for (const key of Object.keys(localStorage))
                if (key.startsWith(prefix + id + ':')) localStorage.removeItem(key);
            await attach(null);
            publishMenu('login');
            showAuthComplete('账号已删除', '可以登录另一个账号或创建新账号。');
        });
        button('返回', body, showPanel);
    }

    async function showHistory(offset = 0) {
        startPanel('history', '账号对局', '每次出发，都在这里留下足迹。');
        const data = await request('/me/matches?offset=' + offset);
        if (showing !== 'history') return;
        if (!data.items.length) {
            const empty = element('div', '', body);
            empty.className = 'history-empty';
            element('strong', '还没有对局记录', empty);
            element('p', '使用账号开始冒险后，进行中与已结算的对局会在这里显示。', empty);
        }
        const list = element('div', '', body);
        list.className = 'history-list';
        for (const row of data.items) {
            const card = element('article', '', list);
            card.className = 'history-entry';
            const words = element('div', '', card);
            element('h3', playerNames[row.character_id] || '冒险记录', words);
            element('small', (difficultyNames[row.difficulty] || '标准') + '难度', words);
            if (row.started_at) {
                const timestamp = /([zZ]|[+-]\d{2}:\d{2})$/.test(row.started_at) ? row.started_at : row.started_at + 'Z';
                element('small', new Date(timestamp).toLocaleDateString('zh-CN', { timeZone: 'Asia/Shanghai' }), words);
            }
            const result = row.result ? (results[row.result.result] || '已结算') : '进行中';
            const outcome = element('div', '', card);
            outcome.className = 'history-outcome';
            outcome.dataset.result = row.result?.result || 'active';
            element('strong', result, outcome);
            if (row.result) element('small', '第 ' + row.result.term + ' 学年', outcome);
        }
        const actions = element('div', '', body);
        actions.className = 'history-actions';
        if (offset) button('上一页', actions, () => showHistory(Math.max(0, offset - 20)));
        if (data.next_offset !== null) button('下一页', actions, () => showHistory(data.next_offset));
        button('返回游戏记录', actions, closePanel);
    }

    async function showStats() {
        if (!flags.admin || menuState !== 'ready' || account?.role !== 'admin') throw new Error('admin_required');
        const user = await readAccount();
        if (user?.user_id !== account.user_id || user?.role !== 'admin') {
            if (user?.user_id === account.user_id) { account = user; publishMenu('ready', statuses.admin_required); }
            dialog.close();
            throw new Error('admin_required');
        }
        startPanel('admin', '管理统计', '玩家活跃与对局完成情况');
        const metrics = element('section', '', body);
        metrics.setAttribute('aria-live', 'polite');
        element('p', '正在读取统计…', metrics);
        const filters = element('details', '', body);
        filters.className = 'account-stats-filters';
        element('summary', '筛选与日期', filters);
        const form = element('form', '', filters);
        form.className = 'account-stats-form';
        const now = new Date(Date.now() + 8 * 3600000).toISOString().slice(0, 10);
        const week = new Date(Date.now() - 6 * 86400000 + 8 * 3600000).toISOString().slice(0, 10);
        field(form, '北京时间起日', 'start', 'date', week);
        field(form, '北京时间止日', 'end', 'date', now);
        for (const [key, text] of [['version', '版本'], ['character', '角色编号'], ['difficulty', '难度']]) {
            field(form, text, key).required = false;
        }
        formSubmit(form, '查询', async values => {
            let rows;
            try { rows = await request('/admin/stats?' + new URLSearchParams(values)); }
            catch (error) {
                metrics.replaceChildren();
                element('p', '统计暂不可用，请重试查询。', metrics);
                filters.open = true;
                throw error;
            }
            if (showing !== 'admin') return;
            metrics.replaceChildren();
            element('p', values.start + ' 至 ' + values.end + ' · 北京时间', metrics).className = 'account-intro';
            const totals = element('div', '', metrics);
            totals.className = 'account-stats-totals';
            totals.setAttribute('aria-label', '注册账号 ' + rows.registered + ' · 独立游客浏览器 ' + rows.visitors);
            for (const [label, count] of [['当前注册账号', rows.registered], ['区间独立游客浏览器', rows.visitors]]) {
                const card = element('div', '', totals);
                element('small', label, card);
                element('strong', String(count), card);
            }
            const scroller = element('div', '', metrics);
            scroller.className = 'account-stats-table';
            scroller.tabIndex = 0;
            scroller.setAttribute('role', 'region');
            scroller.setAttribute('aria-label', '各版本对局统计，可横向滚动');
            const table = element('table', '', scroller);
            element('caption', '对局漏斗 · 按开局日期统计', table);
            const header = element('tr', '', element('thead', '', table));
            for (const label of ['版本', '开局账号', '开局', '完成首战', '完成整局']) {
                element('th', label, header).scope = 'col';
            }
            const entries = element('tbody', '', table);
            for (const row of rows.activity) {
                const entry = element('tr', '', entries);
                for (const value of [row.game_version || '全部版本', row.accounts, row.started, row.first_battles, row.finished])
                    element('td', String(value), entry);
            }
            if (!rows.activity.length) element('p', '此筛选范围内还没有开局记录。', metrics);
            element('small', '游客按浏览器去重，跨设备可能重复。注册账号数不受版本筛选影响。', metrics);
        });
        button('返回主菜单', body, closePanel);
        form.requestSubmit();
    }

    function decode(text) {
        if (!text || text === 'invalid') return null;
        return JSON.parse(text);
    }

    function key(slot, identity = account.user_id) { return identity + ':slot:' + slot; }
    function checksum(snapshot) { return decode(snapshot)?.checksum || ''; }
    function slotMeta(slot) { return storageGet(key(slot), null); }
    function remember(slot, version, hash) { return storageSet(key(slot), { version, hash }); }

    function acceptSave(slot, remote) {
        const applied = game('restore', slot, remote.snapshot);
        if (applied !== 'ok') {
            setStatus('存档无法读取或当前仍有冒险，请保留原件。');
            return false;
        }
        remember(slot, remote.cloud_revision, checksum(remote.snapshot));
        conflicts.delete(slot);
        return true;
    }

    async function syncFromCloud() {
        if (exited || !flags.cloud || !account || !closed || !visible || pullBusy || uploadBusy) return;
        pullBusy = true;
        const id = account.user_id;
        try {
            for (const slot of slots) {
                const remote = await request('/me/saves/' + slot);
                if (exited || account?.user_id !== id || !closed || !visible) return;
                const local = game('read', slot);
                if (local === 'invalid') {
                    setStatus('本机有损坏的存档，请在游戏中检查备份。');
                    continue;
                }
                const meta = slotMeta(slot);
                if (checksum(local) === checksum(remote.snapshot)) {
                    remember(slot, remote.cloud_revision, checksum(local));
                    conflicts.delete(slot);
                } else if ((!local || meta?.hash === checksum(local)) && remote.snapshot) {
                    acceptSave(slot, remote);
                } else if (!remote.snapshot || meta?.version === remote.cloud_revision) {
                    remember(slot, remote.cloud_revision, checksum(remote.snapshot));
                    conflicts.delete(slot);
                    scheduleUpload(false);
                } else if (slot === 'profile') {
                    const joined = game('merge_profile', local, remote.snapshot);
                    if (joined && acceptSave(slot, { ...remote, snapshot: joined })) {
                        remember(slot, remote.cloud_revision, checksum(remote.snapshot));
                        scheduleUpload(true);
                    } else conflicts.set(slot, remote);
                } else conflicts.set(slot, remote);
            }
            if (conflicts.size) setStatus(statuses.save_conflict);
            else if (!needsUpload && !status.startsWith('存档无法')) setStatus('云存档已同步。');
        } catch (error) {
            setStatus(statuses[error.message] || '云端暂不可用，本机副本可继续使用。');
        } finally { pullBusy = false; }
    }

    function scheduleUpload(immediate) {
        if (!flags.cloud || !account) return;
        needsUpload = true;
        if (!conflicts.size) setStatus('本机已保存 · 待同步');
        const now = Date.now();
        uploadSince ||= now;
        clearTimeout(uploadTimer);
        uploadTimer = setTimeout(flushSaves, immediate ? 0 : Math.max(0, Math.min(5000, 15000 - (now - uploadSince))));
    }

    async function writeSlot(slot, snapshot, version, identity) {
        const hash = checksum(snapshot);
        const pendingKey = key(slot, identity) + ':request';
        const pending = storageGet(pendingKey, {});
        const requestId = pending.hash === hash && pending.version === version ? pending.id : crypto.randomUUID();
        storageSet(pendingKey, { id: requestId, hash, version });
        const saved = await request('/me/saves/' + slot, 'PUT', {
            expected_cloud_revision: version, request_id: requestId, snapshot,
        }, identity);
        if (account?.user_id === identity) {
            remember(slot, saved.cloud_revision, hash);
            storageSet(pendingKey, undefined);
        }
    }

    async function flushSaves() {
        if (exited || !flags.cloud || !account || !needsUpload) return;
        if (uploadBusy || pullBusy) { uploadTimer = setTimeout(flushSaves, 800); return; }
        uploadBusy = true;
        needsUpload = false;
        uploadSince = 0;
        const id = account.user_id;
        try {
            for (const slot of slots) {
                if (exited || account?.user_id !== id) return;
                const snapshot = game('read', slot);
                if (!snapshot || snapshot === 'invalid' || conflicts.has(slot)) continue;
                let meta = slotMeta(slot);
                if (!meta) {
                    const remote = await request('/me/saves/' + slot, 'GET', undefined, id);
                    if (exited || account?.user_id !== id) return;
                    const hash = checksum(remote.snapshot);
                    if (remote.snapshot && hash !== checksum(snapshot)) {
                        conflicts.set(slot, remote);
                        continue;
                    }
                    meta = { version: remote.cloud_revision, hash };
                    remember(slot, meta.version, meta.hash);
                }
                if (meta.hash === checksum(snapshot)) continue;
                try { await writeSlot(slot, snapshot, meta.version, id); }
                catch (error) {
                    if (error.response?.detail !== 'save_conflict') throw error;
                    conflicts.set(slot, error.response.current);
                }
            }
            setStatus(conflicts.size ? statuses.save_conflict : '云存档已同步。');
        } catch (error) {
            setStatus(statuses[error.message] || '本机已保存 · 等待网络恢复');
            if (account?.user_id === id && error.status !== 401 && (!error.status || error.status >= 500)) {
                needsUpload = true;
                uploadTimer = setTimeout(flushSaves, 20000);
            }
        } finally { uploadBusy = false; }
    }

    function saveLabel(snapshot) {
        const data = decode(snapshot);
        if (!data) return '无存档';
        const run = data.payload.run;
        if (!run) return '个人档案';
        return [playerNames[run.character_id], '第' + run.term + '学年', '进度 ' + data.revision].join(' · ');
    }

    async function showSaves() {
        startPanel('saves', '云存档');
        await syncFromCloud();
        if (showing !== 'saves') return;
        for (const slot of slots) {
            const remote = await request('/me/saves/' + slot);
            if (showing !== 'saves') return;
            const local = game('read', slot);
            const card = element('section', '', body);
            card.className = 'account-save-card';
            element('h3', slot === 'current_run' ? '当前冒险' : '个人进度', card);
            element('p', '本机 · ' + saveLabel(local), card);
            element('p', '云端 · ' + saveLabel(remote.snapshot), card);
            if (remote.saved_at) element('small', '云端保存于 ' + new Date(remote.saved_at).toLocaleString('zh-CN'), card);
            if (!conflicts.has(slot)) continue;
            element('p', '设备进度不同，请选择要继续的版本。', card);
            button('使用云端版本', card, async () => {
                if (acceptSave(slot, remote)) await showSaves();
            });
            button('保留本机版本并上传', card, async () => {
                await writeSlot(slot, local, remote.cloud_revision, account.user_id);
                conflicts.delete(slot);
                await showSaves();
            });
        }
        const guest = game('read_guest', 'current_run');
        const profile = game('read_guest', 'profile');
        if (decode(guest) || decode(profile)) {
            button('导入本机游客进度', body, () => showImport(guest, profile));
        }
        button('检查同步', body, async () => { await syncFromCloud(); await showSaves(); });
        button('查看上一份云端备份', body, showCloudBackup);
        button('返回设置与存档', body, closePanel);
    }

    async function showCloudBackup() {
        startPanel('backup', '上一份云端备份');
        const previous = await request('/me/saves/current_run?previous=true');
        if (showing !== 'backup') return;
        element('p', saveLabel(previous.snapshot), body);
        if (previous.snapshot) {
            button('恢复这份备份', body, async () => {
                const current = await request('/me/saves/current_run');
                if (game('restore', 'current_run', previous.snapshot) !== 'ok') throw new Error('restore_failed');
                await writeSlot('current_run', previous.snapshot, current.cloud_revision, account.user_id);
                conflicts.delete('current_run');
                await showSaves();
            });
        }
        button('返回', body, showSaves);
    }

    function showImport(guest, profile) {
        startPanel('import', '导入本机游客进度');
        const local = game('read', 'current_run');
        const history = Object.values(decode(profile)?.payload.summaries_by_run_id || {});
        element('p', '游客 · ' + saveLabel(guest) + ' · ' + history.length + ' 条已结算对局。', body);
        element('p', '账号本机 · ' + saveLabel(local) + '。如与云端不同，导入后可以选择继续哪一份。', body);
        button('确认导入', body, async () => {
            if (decode(guest) && game('restore', 'current_run', guest) !== 'ok') throw new Error('import_failed');
            if (decode(profile)) {
                const own = game('read', 'profile');
                const merged = own ? game('merge_profile', own, profile) : profile;
                if (!merged || game('restore', 'profile', merged) !== 'ok') throw new Error('import_failed');
                const rows = history.map(row => ({
                    run_id: row.run_id, character_id: row.character_id, difficulty: row.difficulty,
                    manifest_id: row.manifest_id, game_version: 'imported', summary: summary(row),
                }));
                for (let index = 0; index < rows.length; index += 50)
                    await request('/me/matches/import', 'POST', rows.slice(index, index + 50));
            }
            // Require explicit conflict selection when an existing cloud run differs.
            if (decode(guest)) storageSet(key('current_run'), undefined);
            await showSaves();
        });
        button('返回', body, showSaves);
    }

    function summary(row) {
        return { result: row.result, reason: row.reason, term: row.term, ending_id: row.ending_id };
    }

    function record(kind, runJson, detailsJson) {
        if (!account) return;
        if (kind === 'checkpoint') { scheduleUpload(true); return; }
        const run = JSON.parse(runJson);
        if (buildVersion !== '__KAPAI_' + 'BUILD_VERSION__') run.game_version = buildVersion;
        const detail = JSON.parse(detailsJson);
        const key = account.user_id + ':event:' + run.run_id + ':' + kind;
        if (!storageGet(key, null))
            storageSet(key, { kind, run, detail, event_id: crypto.randomUUID() });
        if (kind !== 'start') scheduleUpload(true);
        queueMicrotask(flushEvents);
    }

    async function flushEvents() {
        if (exited || !account || eventBusy) return;
        eventBusy = true;
        const id = account.user_id;
        try {
            const keys = Object.keys(localStorage).filter(key => key.startsWith(prefix + id + ':event:'));
            const entries = keys.map(key => [key.slice(prefix.length), storageGet(key.slice(prefix.length), null)])
                .filter(([, event]) => event);
            const rank = { start: 0, first_battle: 1, finish: 2 };
            entries.sort(([, a], [, b]) => rank[a.kind] - rank[b.kind]);
            const blockedRuns = new Set(entries.filter(([, event]) => event.blocked)
                .map(([, event]) => event.run.run_id));
            for (const [key, event] of entries) {
                if (account?.user_id !== id) return;
                if (blockedRuns.has(event.run.run_id)) continue;
                try {
                    const { match_id } = await request('/matches/start', 'POST', event.run, id);
                    if (event.kind === 'first_battle') {
                        await request('/events', 'POST', {
                            event_type: 'first_battle_completed', event_id: event.event_id,
                            match_id, result: event.detail.result,
                        }, id);
                    } else if (event.kind === 'finish') {
                        await request('/matches/' + match_id + '/finish', 'POST', event.detail, id);
                    }
                    storageSet(key, undefined);
                } catch (error) {
                    if (error.status !== 409) throw error;
                    blockedRuns.add(event.run.run_id);
                    storageSet(key, { ...event, blocked: true });
                    setStatus(statuses[error.message] || '该局记录有冲突，其他对局会继续同步。');
                }
            }
        } catch {
            // A connectivity or session failure leaves the event queued.
        } finally { eventBusy = false; }
    }

    function openAccountLink() {
        const token = /^#account-(verify|reset)=([\w-]{30,100})$/.exec(location.hash);
        if (!active || !token) return;
        history.replaceState(null, '', location.pathname + location.search);
        showToken(token[1], token[2]);
    }

    async function boot() {
        if (connecting) return;
        connecting = true;
        const confirmingAccount = !guestSelected;
        if (confirmingAccount) publishMenu('checking');
        else if (menuState !== 'guest') publishMenu('guest');
        try {
            flags = await request('/features', 'GET', undefined, '');
            active = flags.accounts === true;
            game('account_features', String(active));
            if (!confirmingAccount) {
                if (guestSelected && active) {
                    openAccountLink();
                    void visitor().catch(() => {});
                } else if (active && menuState === 'unavailable') {
                    publishMenu('login');
                }
                return;
            }
            if (!active) throw new Error('feature_disabled');
            const user = await readAccount();
            if (user && !await attach(user)) {
                publishMenu('unavailable', statuses.account_busy);
                return;
            }
            if (!user && closed) await attach(null);
            if (user) await syncFromCloud();
            publishMenu(user ? 'ready' : 'login');
            openAccountLink();
            void flushEvents();
            if (!user) void visitor().catch(() => {});
        } catch {
            if (confirmingAccount) publishMenu('unavailable', '暂时无法确认账号登录状态。');
        } finally {
            connecting = false;
        }
    }

    async function confirmPlay(developerTools = false) {
        if (menuState === 'guest') {
            game('play_confirmed', String(!developerTools && guestSelected && !account));
            return;
        }
        let allowed = false;
        try {
            const user = await readAccount();
            allowed = menuState === 'ready' && !!user && account?.user_id === user.user_id;
            if (allowed) {
                const roleChanged = account.role !== user.role;
                account = user;
                if (developerTools && user.role !== 'admin') {
                    allowed = false;
                    publishMenu('ready', statuses.admin_required);
                } else if (roleChanged) {
                    allowed = false;
                    publishMenu('ready');
                }
            } else {
                if (closed) await attach(null);
                publishMenu('login', '登录状态已变化，请重新登录。');
            }
        } catch {
            publishMenu('unavailable', '暂时无法确认登录状态，请重新连接。');
        } finally {
            game('play_confirmed', String(allowed));
        }
    }

    window.kapaiAccounts = {
        connectGame(callback) {
            game = (...args) => {
                reply = undefined;
                callback(...args);
                return reply;
            };
            void boot();
        },
        reply(value) { reply = value; },
        showMenu(show, canSwitch) {
            const changed = visible !== show || closed !== canSwitch;
            visible = show;
            closed = canSwitch;
            if (changed && visible && closed && menuState === 'ready') queueMicrotask(syncFromCloud);
        },
        saved() { scheduleUpload(false); },
        priority() { scheduleUpload(true); },
        openAccount(registering) {
            if (menuState === 'unavailable') { void boot(); return; }
            if (menuState === 'checking') return;
            if (registering && flags.registration && menuState === 'login') showRegister();
            else showPanel();
        },
        enterGuest() { void perform(enterGuest); },
        exitGuest() { queueMicrotask(showLogout); },
        openSection(section) {
            queueMicrotask(() => perform(async () => {
                if (section === 'quit') {
                    clearTimeout(uploadTimer);
                    visible = false;
                    exited = true;
                    window.kapaiExitGame?.();
                    return;
                }
                if (menuState !== 'ready' || !account) return;
                if (section === 'saves' && flags.cloud) requireClosed('云存档', showSaves, 'settings');
                else if (section === 'history') await showHistory();
                else if (section === 'stats') await showStats();
            }));
        },
        confirmPlay(developerTools = false) { queueMicrotask(() => confirmPlay(developerTools)); },
        openPrivacy() { if (active) showPrivacy(); },
        record,
    };

    window.addEventListener('online', () => {
        if (menuState === 'unavailable' || (menuState === 'guest' && !active)) void boot();
        else { void syncFromCloud(); void flushSaves(); void flushEvents(); }
    });
    window.addEventListener('hashchange', openAccountLink);
    document.addEventListener('visibilitychange', () => {
        if (document.hidden) void flushSaves();
        else void syncFromCloud();
    });
    window.addEventListener('focus', () => { void syncFromCloud(); void flushEvents(); });
    window.setInterval(() => { void flushEvents(); }, 20000);
})();
