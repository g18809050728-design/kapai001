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
        feedback_conflict: '这次反馈已提交，请关闭面板后重新填写。',
        feedback_not_found: '这条反馈已不可用。',
        feedback_changed: '反馈已被其他管理员更新，请重新打开详情后再保存。',
        export_too_many_rows: '结果超过 5000 行，请缩小查询范围后再导出。',
        export_invalid_file: '未收到有效的 XLSX 文件，请稍后重试。',
        maintenance_nickname_unchanged: '新昵称与当前昵称相同。',
        maintenance_player_missing: '此账号不存在，或已不在可维护范围内。',
        maintenance_player_changed: '资料已被修改，请返回玩家资料重新检查。',
        invalid_range: '请选择有效日期，结束日期不能早于开始日期，范围最多 367 天。',
        stats_record_not_found: '这条统计记录已不可用。',
        stats_record_changed: '记录已更新，请重新打开详情后再操作。',
        stats_record_excluded: '该记录已移出统计，请先恢复。',
        screenshot_invalid: '请选择可打开的静态 PNG、JPEG 或 WebP 截图。',
        screenshot_too_large: '截图过大，请裁剪或压缩后重试。',
        screenshot_dimensions: '截图分辨率过高，请裁剪后重试。',
        screenshots_loading: '正在读取截图，请稍等片刻再提交。',
        result_conflict: '该局已有不同结算，请核对本地对局。',
        database_unavailable: '账号服务暂时不可用，本机进度仍可保存。',
    };
    const playerNames = { P01: '林序', P02: '许知微', P03: '沈见章', P04: '唐以宁' };
    const difficultyNames = { relaxed: '轻松', normal: '标准', hard: '困难' };
    const results = { won: '胜利', lost: '失败', abandoned: '已放弃' };
    const feedbackCategories = { bug: '游戏问题', suggestion: '改进建议', other: '其他反馈' };
    const screenshotTypes = ['image/png', 'image/jpeg', 'image/webp'];
    const screenshotSizeLimit = 2 * 1024 * 1024;
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
            if (showing.startsWith('feedback') || showing.startsWith('admin')) body.replaceChildren();
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
        dialog.classList.toggle('workspace-dialog', name.startsWith('feedback') || name.startsWith('admin'));
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
        const input = labeledControl(form, label, key, 'input');
        input.type = type;
        input.value = value;
        input.required = true;
        return input;
    }

    function labeledControl(form, label, key, tag) {
        const group = element('div', '', form);
        group.className = 'account-field';
        const caption = element('label', label, group);
        const input = element(tag, '', group);
        input.id = 'account-field-' + key;
        caption.htmlFor = input.id;
        input.name = key;
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

    function formSubmit(form, label, handler, actions = null) {
        const feedback = element('p', '', form);
        feedback.className = 'account-form-error';
        feedback.setAttribute('role', 'alert');
        const submit = element('button', label, actions || form);
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
            const values = Object.fromEntries(new FormData(form));
            const mutable = form.classList.contains('workspace-form')
                ? [...body.querySelectorAll('button, input, textarea, select')].filter(control => !control.disabled) : [];
            mutable.forEach(control => { control.disabled = true; });
            try {
                await handler(values);
            } catch (error) {
                feedback.textContent = statuses[error.message] || '操作失败，请稍后重试。';
            } finally {
                mutable.forEach(control => { control.disabled = false; });
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
        element('p', '删除账号会清除该账号的云存档、对局记录、反馈和截图。请输入密码确认。', body);
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

    function feedbackCategory(parent, label, selected, all = false) {
        const select = labeledControl(parent, label, 'category', 'select');
        if (all) element('option', '全部类型', select).value = '';
        for (const [value, name] of Object.entries(feedbackCategories)) {
            element('option', name, select).value = value;
        }
        select.value = selected;
        return select;
    }

    function readScreenshot(file) {
        return new Promise((resolve, reject) => {
            const reader = new FileReader();
            reader.onload = () => resolve(String(reader.result));
            reader.onerror = () => reject(new Error('screenshot_invalid'));
            reader.readAsDataURL(file);
        });
    }

    function showFeedback() {
        startPanel('feedback', '问题反馈', '遇到问题或有改进想法？告诉我们发生了什么。');
        const form = element('form', '', body);
        form.className = 'workspace-form';
        const basics = workspaceGrid(form, 'workspace-compose');
        feedbackCategory(basics, '反馈类型（必填）', 'bug');
        const subject = field(basics, '标题（必填）', 'title');
        subject.placeholder = '例如：首战结束后无法领取奖励';
        subject.maxLength = 100;
        const description = labeledControl(form, '详细说明（必填）', 'description', 'textarea');
        description.required = true;
        description.maxLength = 3000;
        description.rows = 4;
        counter(subject);
        counter(description);
        description.placeholder = '你当时在哪个页面？做了什么？实际发生了什么？';
        const attachPanel = element('section', '', form);
        attachPanel.className = 'workspace-attachments';
        element('h3', '问题截图（选填）', attachPanel);
        const input = field(attachPanel, '添加截图（选填）', 'screenshots', 'file');
        input.accept = screenshotTypes.join(',');
        input.multiple = true;
        input.required = false;
        input.hidden = true;
        input.className = 'feedback-file-input';
        input.parentElement.firstElementChild.hidden = true;
        const choose = button('选择截图', input.parentElement, () => input.click());
        hint(input, '最多 3 张，每张不超过 2 MiB。支持 PNG、JPEG、WebP。提交后仅管理员可查看。');
        choose.setAttribute('aria-describedby', input.id + '-hint');
        const uploadStatus = element('small', '', input.parentElement);
        uploadStatus.setAttribute('role', 'status');
        const gallery = element('ul', '', attachPanel);
        gallery.className = 'feedback-screenshots';
        const screenshots = [];
        let submissionId;
        let uploading = false;
        form.addEventListener('input', event => { if (event.target !== input) submissionId = undefined; });
        input.addEventListener('change', async () => {
            const files = Array.from(input.files);
            input.value = '';
            if (dialog.dataset.busy || !files.length) return;
            if (files.length + screenshots.length > 3) {
                uploadStatus.textContent = '最多可添加 3 张截图，请移除一张或减少选择。';
                return;
            }
            if (files.some(file => file.size > screenshotSizeLimit)) {
                uploadStatus.textContent = statuses.screenshot_too_large;
                return;
            }
            if (files.some(file => !screenshotTypes.includes(file.type) || !file.size)) {
                uploadStatus.textContent = statuses.screenshot_invalid;
                return;
            }
            uploading = true;
            input.disabled = true;
            choose.disabled = true;
            try {
                const previews = await Promise.all(files.map(readScreenshot));
                if (!gallery.isConnected || !dialog.open) return;
                for (const [index, data] of previews.entries()) {
                    const entry = { data, file: files[index] };
                    screenshots.push(entry);
                    const item = element('li', '', gallery);
                    const img = element('img', '', item);
                    img.alt = entry.file.name;
                    img.src = data;
                    const remove = button('移除', item, () => {
                        screenshots.splice(screenshots.indexOf(entry), 1);
                        item.remove();
                        submissionId = undefined;
                        uploadStatus.textContent = `已选 ${screenshots.length} 张截图`;
                        choose.focus();
                    });
                    remove.setAttribute('aria-label', '移除截图 ' + entry.file.name);
                }
                submissionId = undefined;
                uploadStatus.textContent = `已选 ${screenshots.length} 张截图`;
            } catch (error) {
                uploadStatus.textContent = statuses[error.message] || statuses.screenshot_invalid;
            } finally {
                uploading = false;
                input.disabled = false;
                choose.disabled = false;
            }
        });
        const actions = workspaceActions(form);
        button('取消', actions, closePanel);
        formSubmit(form, '提交反馈', async values => {
            if (uploading) throw new Error('screenshots_loading');
            if (!values.title.trim() || !values.description.trim()) throw new Error('invalid_input');
            submissionId ??= crypto.randomUUID();
            const receipt = await request('/feedback', 'POST', {
                submission_id: submissionId,
                category: values.category,
                title: values.title.trim(),
                description: values.description.trim(),
                build_version: buildVersion,
                screenshots: screenshots.map(({data}) => data.slice(data.indexOf(',') + 1)),
            });
            startPanel('feedback-sent', '反馈已提交', '管理员可以查看你的反馈。');
            element('p', '反馈编号 ' + receipt.feedback_id, body).className = 'feedback-text';
            button('返回游戏', body, closePanel).className = 'account-primary';
        }, actions);
    }

    const feedbackStates = {new: '待处理', reviewing: '处理中', resolved: '已解决', archived: '已归档'};
    const sortOptions = {newest: '从新到旧', oldest: '从旧到新'};
    const statsSources = {automatic: '自动记录', adjusted: '已修正', manual: '人工补录'};
    const characters = Object.fromEntries(Object.entries(playerNames).map(([id, name]) => [id, `${name} · ${id}`]));
    const difficulties = difficultyNames;
    const bjDate = days => new Date(Date.now() + (8 + 24 * days) * 3600000).toISOString().slice(0, 10);
    const bjTime = time => new Date(time).toLocaleString('zh-CN', {timeZone: 'Asia/Shanghai', hour12: false});
    const statsDefaults = () => ({start: bjDate(-6), end: bjDate(0), version: '', character: '', difficulty: '',
        q: '', source: '', state: 'included', sort: 'newest', offset: 0});
    const feedbackDefaults = {q: '', category: '', state: 'all', sort: 'newest', offset: 0};

    function workspaceGrid(parent, extra = '') {
        const grid = element('div', '', parent);
        grid.className = `workspace-grid ${extra}`;
        return grid;
    }

    function workspaceActions(parent) {
        const actions = element('div', '', parent);
        actions.className = 'workspace-actions';
        return actions;
    }

    function counter(input) {
        const count = element('small', '', input.parentElement);
        count.className = 'workspace-counter';
        count.id = input.id + '-count';
        input.setAttribute('aria-describedby', count.id);
        const update = () => { count.textContent = `${input.value.length} / ${input.maxLength}`; };
        input.addEventListener('input', update);
        update();
    }

    function options(parent, label, name, values, selected) {
        const select = labeledControl(parent, label, name, 'select');
        for (const [value, text] of Object.entries(values)) element('option', text, select).value = value;
        if (selected && !Object.hasOwn(values, selected)) element('option', selected, select).value = selected;
        select.value = selected;
        return select;
    }

    function optional(parent, label, name, value, max = 100, type = 'text', placeholder = '') {
        const input = field(parent, label, name, type, value);
        input.required = false;
        input.maxLength = max;
        input.placeholder = placeholder;
        return input;
    }

    function badge(parent, text, tone = '') {
        const node = element('span', text, parent);
        node.className = 'workspace-badge';
        node.dataset.tone = tone;
        return node;
    }

    function workspaceResult(parent) {
        const region = element('section', '', parent);
        region.className = 'workspace-result';
        return region;
    }

    function resultText(parent, text) {
        const line = element('p', text, parent);
        line.className = 'workspace-result-text';
        line.setAttribute('role', 'status');
        return line;
    }

    function pager(parent, page, offset, openPage) {
        const actions = workspaceActions(parent);
        if (offset) button('上一页', actions, () => openPage(Math.max(0, offset - 20)));
        if (page.next_offset !== null) button('下一页', actions, () => openPage(page.next_offset));
    }

    function recordCard(parent, heading, meta, tags, open) {
        const row = button('', parent, open);
        row.className = 'workspace-record';
        const info = element('span', '', row);
        info.className = 'workspace-record-info';
        element('strong', heading, info);
        element('small', meta, info);
        const labels = element('span', '', row);
        labels.className = 'workspace-record-tags';
        for (const [text, tone] of tags) badge(labels, text, tone);
        const arrow = element('span', '›', row);
        arrow.setAttribute('aria-hidden', 'true');
        arrow.className = 'workspace-chevron';
        return row;
    }

    async function showFeedbackInbox(state = feedbackDefaults, message = '') {
        if (!flags.admin || account?.role !== 'admin') throw new Error('admin_required');
        startPanel('feedback-admin', '反馈管理', '检索玩家提交的问题与建议，并记录处理进度。');
        let activeFilters = state;
        button('数据库维护', workspaceActions(body), () => showDataMaintenance(undefined, () => showFeedbackInbox(activeFilters)));
        const form = element('form', '', body);
        form.className = 'workspace-form workspace-filters';
        optional(form, '搜索反馈', 'q', state.q, 100, 'search', '标题、正文、玩家、版本或反馈编号');
        const filters = workspaceGrid(form);
        feedbackCategory(filters, '反馈类型', state.category, true);
        options(filters, '处理状态', 'state', {all: '全部状态', active: '待处理与处理中', ...feedbackStates}, state.state);
        options(filters, '排序', 'sort', sortOptions, state.sort);
        const actions = workspaceActions(form);
        button('清空筛选', actions, () => showFeedbackInbox());
        const list = workspaceResult(body);
        formSubmit(form, '搜索', values => render({...values, offset: 0}), actions);

        async function render(filters, banner = '') {
            list.replaceChildren();
            if (banner) resultText(list, banner);
            const progress = resultText(list, '正在读取反馈…');
            const params = new URLSearchParams(filters);
            if (!filters.category) params.delete('category');
            let page;
            try { page = await request('/admin/feedback?' + params); }
            catch (error) {
                progress.textContent = '暂时无法读取反馈。';
                if (error.status !== 401 && error.status !== 403) button('重试', list, () => render(filters));
                if (list.isConnected && dialog.open) throw error;
                return;
            }
            if (!list.isConnected || !dialog.open || !progress.isConnected) return;
            if (!page.items.length && filters.offset) return render({...filters, offset: Math.max(0, filters.offset - 20)}, banner);
            progress.textContent = page.items.length ? `共 ${page.total} 条反馈 · 第 ${1 + Math.floor(filters.offset / 20)} 页` : '没有符合条件的反馈。';
            activeFilters = filters;
            exportControls(list, 'feedback', params);
            const rows = element('div', '', list);
            rows.className = 'feedback-list';
            for (const item of page.items) {
                const tags = [[feedbackCategories[item.category] || item.category, ''], [feedbackStates[item.status], item.status]];
                if (item.screenshot_count) tags.push([`${item.screenshot_count} 张截图`, '']);
                recordCard(rows, item.title, `${item.nickname} · ${bjTime(item.created_at)}${item.build_version ? ' · ' + item.build_version : ''}`,
                    tags, () => showFeedbackDetail(item.feedback_id, filters));
            }
            pager(list, page, filters.offset, offset => showFeedbackInbox({...filters, offset}));
        }
        await render(state, message);
    }

    async function showFeedbackDetail(id, filters) {
        startPanel('feedback-detail', '反馈详情');
        button('← 返回反馈列表', workspaceActions(body), () => showFeedbackInbox(filters));
        const details = workspaceResult(body);
        const progress = resultText(details, '正在读取详情…');
        const route = '/admin/feedback/' + encodeURIComponent(id);
        let item;
        try { item = await request(route); }
        catch (error) {
            if (!details.isConnected || !dialog.open) return;
            progress.textContent = '暂时无法读取详情。';
            throw error;
        }
        if (!details.isConnected || !dialog.open) return;
        details.replaceChildren();
        const article = element('article', '', details);
        article.className = 'workspace-sheet';
        const tags = workspaceActions(article);
        badge(tags, feedbackCategories[item.category] || item.category);
        badge(tags, feedbackStates[item.status], item.status);
        element('h3', item.title, article).className = 'feedback-text';
        element('p', `${item.nickname}${item.username && item.username !== item.nickname ? ' · ' + item.username : ''} · ${bjTime(item.created_at)}（北京时间）`, article).className = 'account-intro feedback-text';
        element('small', `编号 ${id}${item.build_version ? ' · 版本 ' + item.build_version : ''}`, article).className = 'feedback-text';
        element('p', item.description, article).className = 'feedback-text workspace-description';
        if (item.screenshots.length) {
            element('h4', `截图 · ${item.screenshots.length} 张`, article);
            const gallery = element('ul', '', article);
            gallery.className = 'feedback-screenshots';
            for (const shot of item.screenshots) {
                const link = element('a', '', element('li', '', gallery));
                link.href = api + route + '/screenshots/' + shot.position;
                link.target = '_blank';
                link.rel = 'noopener';
                const img = element('img', '', link);
                img.alt = `截图 ${shot.position}（${shot.width} × ${shot.height}）`;
                img.loading = 'lazy';
                img.src = link.href;
                element('span', `查看截图 ${shot.position} 大图`, link);
            }
        }
        const form = element('form', '', details);
        form.className = 'workspace-sheet workspace-form';
        element('h3', '处理反馈', form);
        options(form, '处理状态', 'status', feedbackStates, item.status);
        const note = labeledControl(form, '内部备注（仅管理员可见）', 'note', 'textarea');
        note.maxLength = 1600;
        note.rows = 3;
        note.value = item.note;
        counter(note);
        element('small', '归档不会删除玩家原文或截图，可随时更改状态恢复。', form);
        formSubmit(form, '保存处理结果', async values => {
            await request(route, 'PATCH', {...values, updated_at: item.updated_at});
            await showFeedbackInbox(filters, '处理结果已保存。');
        }, workspaceActions(form));
    }

    async function checkAdminWorkspace() {
        if (!flags.admin || menuState !== 'ready' || account?.role !== 'admin') throw new Error('admin_required');
        const user = await readAccount();
        if (user?.user_id !== account?.user_id || user?.role !== 'admin') {
            if (user && user.user_id === account?.user_id) { account = user; publishMenu('ready', statuses.admin_required); }
            dialog.close();
            throw new Error('admin_required');
        }
    }

    async function showStats() {
        await checkAdminWorkspace();
        await statsWorkspace();
    }

    function statsDates(parent, filters, form) {
        const group = workspaceGrid(parent);
        for (const [name, label] of [['start', '开始日期（北京时间）'], ['end', '结束日期（北京时间）']]) {
            const input = field(group, label, name, 'date', filters[name]);
            input.min = '2000-01-01';
            input.max = '9998-12-31';
        }
        const buttons = workspaceActions(parent);
        for (const days of [7, 30, 90]) button(`近 ${days} 天`, buttons, () => {
            form.elements.start.value = bjDate(1 - days);
            form.elements.end.value = bjDate(0);
            form.requestSubmit();
        });
    }

    async function statsWorkspace(view = 'overview', filters = statsDefaults(), message = '') {
        const records = view === 'records';
        startPanel('admin', '管理统计', '查看玩家活跃和对局漏斗，检索并维护纳入统计的对局。');
        const nav = element('nav', '', body);
        nav.className = 'workspace-tabs';
        nav.setAttribute('aria-label', '统计视图');
        let current = filters;
        for (const [key, label] of [['overview', '统计概览'], ['records', '对局明细']]) {
            const tab = button(label, nav, () => statsWorkspace(key, {...current, offset: 0}));
            if (key === view) tab.setAttribute('aria-current', 'page');
        }
        button('数据库维护', nav, () => showDataMaintenance(undefined, () => statsWorkspace(view, current)));
        const form = element('form', '', body);
        form.className = 'workspace-form workspace-filters';
        if (records) optional(form, '搜索对局明细', 'q', filters.q, 100, 'search', '对局编号、玩家、版本或操作理由');
        const advanced = element('details', '', form);
        advanced.className = 'workspace-advanced';
        advanced.open = matchMedia('(min-width: 670px)').matches;
        const filterHeading = element('summary', '', advanced);
        const controls = element('div', '', advanced);
        statsDates(controls, filters, form);
        const group = workspaceGrid(controls);
        optional(group, '游戏版本', 'version', filters.version, 80, 'text', '全部版本或完整版本号');
        options(group, '角色', 'character', {'': '全部角色', ...characters}, filters.character);
        options(group, '难度', 'difficulty', {'': '全部难度', ...difficulties}, filters.difficulty);
        if (records) {
            const detailFilters = workspaceGrid(controls);
            options(detailFilters, '记录来源', 'source', {'': '全部来源', ...statsSources}, filters.source);
            options(detailFilters, '统计状态', 'state', {included: '计入统计', excluded: '已移出', all: '全部记录'}, filters.state);
            options(detailFilters, '排序', 'sort', sortOptions, filters.sort);
        }
        const actions = workspaceActions(form);
        button('重置筛选', actions, () => statsWorkspace(view));
        if (records) button('＋ 新增统计记录', actions, () => editStatsRecord(null, current));
        const results = workspaceResult(body);
        formSubmit(form, '查询', values => render({...current, ...values, offset: 0}), actions);

        async function render(options, banner = '') {
            current = options;
            results.replaceChildren();
            if (banner) resultText(results, banner);
            const progress = resultText(results, '正在读取统计…');
            const {start, end, version, character, difficulty, q, source, state, sort, offset} = options;
            const count = [version, character, difficulty, ...(records ? [source, state !== 'included', sort !== 'newest'] : [])].filter(Boolean).length;
            filterHeading.textContent = `日期与筛选 · ${start} 至 ${end}${count ? ` · ${count} 项条件` : ''}`;
            const params = new URLSearchParams({start, end, version, character, difficulty,
                ...(records ? {q, source, state, sort, offset} : {})});
            let data;
            try { data = await request('/admin/stats' + (records ? '/records?' : '?') + params); }
            catch (error) {
                progress.textContent = '暂时无法读取统计，请调整筛选或重试。';
                advanced.open = true;
                if (results.isConnected && dialog.open) throw error;
                return;
            }
            if (!results.isConnected || !dialog.open || !progress.isConnected) return;
            if (!records) {
                progress.textContent = `${start} 至 ${end} · 北京时间`;
                exportControls(results, 'stats', params);
                renderStatsOverview(results, data, options);
                return;
            }
            if (!data.items.length && offset) return render({...options, offset: Math.max(0, offset - 20)}, banner);
            progress.textContent = data.items.length ? `共 ${data.total} 条对局记录 · 第 ${1 + Math.floor(offset / 20)} 页` : '没有符合条件的对局记录。';
            exportControls(results, 'records', params);
            const list = element('div', '', results);
            list.className = 'feedback-list';
            for (const item of data.items) {
                const tags = [[statsSources[item.source], item.source], [item.excluded ? '已移出' : item.finished ? '已结算' : '未结算', item.excluded ? 'archived' : '']];
                recordCard(list, item.nickname || '人工补录', `${bjTime(item.started_at)} · ${item.game_version} · ${item.character_id} · ${difficulties[item.difficulty] || item.difficulty}`,
                    tags, () => showStatsRecord(item.record_id, options));
            }
            pager(results, data, offset, next => statsWorkspace(view, {...options, offset: next}));
        }
        await render(filters, message);
    }

    function renderStatsOverview(parent, data, filters) {
        const format = value => new Intl.NumberFormat('zh-CN').format(Number(value || 0));
        const totals = data.activity.find(row => row.game_version === null);
        const metrics = workspaceGrid(parent, 'workspace-metrics');
        for (const [label, value] of [['累计注册账号', data.registered], ['区间独立游客浏览器', data.visitors],
            ['开局账号', totals?.accounts], ['对局开局', totals?.started]]) {
            const card = element('div', '', metrics);
            element('small', label, card);
            element('strong', format(value), card);
        }
        const funnel = element('section', '', parent);
        funnel.className = 'workspace-sheet';
        element('h3', '对局漏斗', funnel);
        const base = Number(totals?.started || 0);
        for (const [label, value] of [['开局', base], ['完成首战', totals?.first_battles], ['完成整局', totals?.finished]]) {
            const line = element('div', '', funnel);
            line.className = 'workspace-funnel';
            const n = Number(value || 0);
            element('span', label, line);
            const bar = element('progress', '', line);
            bar.max = base || 1;
            bar.value = n;
            bar.setAttribute('aria-label', label);
            element('strong', `${format(n)} · ${base ? Math.round(n / base * 100) + '%' : '—'}`, line);
        }
        element('small', '完成整局表示已结算，不限胜败；人工补录只计对局，不增加开局账号。', funnel);
        const versions = data.activity.filter(row => row.game_version !== null);
        if (!versions.length) resultText(parent, '此筛选范围内还没有计入统计的对局。');
        else {
            const scroller = element('div', '', parent);
            scroller.className = 'account-stats-table workspace-stats-table';
            scroller.tabIndex = 0;
            scroller.setAttribute('role', 'region');
            scroller.setAttribute('aria-label', '版本统计，可横向滚动');
            const table = element('table', '', scroller);
            element('caption', '各版本对局', table);
            const header = element('tr', '', element('thead', '', table));
            for (const label of ['版本', '开局账号', '开局', '首战完成', '已结算', '人工补录']) element('th', label, header).scope = 'col';
            const rows = element('tbody', '', table);
            for (const row of versions) {
                const entry = element('tr', '', rows);
                const cell = element('th', '', entry);
                cell.scope = 'row';
                button(row.game_version, cell, () => statsWorkspace('records', {...filters, version: row.game_version, offset: 0}));
                for (const value of [row.accounts, row.started, row.first_battles, row.finished, row.manual]) element('td', format(value), entry);
            }
        }
        element('small', '游客按浏览器去重，可能跨设备重复；游客数只受日期影响，累计注册数不受筛选影响。', parent);
    }

    const statsRoute = id => '/admin/stats/records' + (id ? '/' + encodeURIComponent(id) : '');

    async function showStatsRecord(id, filters, message = '') {
        startPanel('admin-detail', '对局统计详情');
        button('← 返回对局明细', workspaceActions(body), () => statsWorkspace('records', filters));
        const details = workspaceResult(body);
        const progress = resultText(details, '正在读取记录…');
        let item;
        try { item = await request(statsRoute(id)); }
        catch (error) {
            if (!details.isConnected || !dialog.open) return;
            progress.textContent = '暂时无法读取记录。';
            throw error;
        }
        if (!details.isConnected || !dialog.open) return;
        details.replaceChildren();
        if (message) resultText(details, message);
        const sheet = element('section', '', details);
        sheet.className = 'workspace-sheet';
        const tags = workspaceActions(sheet);
        badge(tags, statsSources[item.source], item.source);
        badge(tags, item.excluded ? '已移出' : '计入统计', item.excluded ? 'archived' : 'resolved');
        element('h3', item.nickname || '人工补录', sheet);
        const facts = element('dl', '', sheet);
        facts.className = 'workspace-facts';
        for (const [label, value] of [['记录编号', id], ['开局时间（北京时间）', bjTime(item.started_at)], ['游戏版本', item.game_version],
            ['角色', characters[item.character_id] || item.character_id], ['难度', difficulties[item.difficulty] || item.difficulty],
            ['首战完成', item.first_battle ? '是' : '否'], ['整局结算', item.finished ? '是' : '否'], ['最近操作理由', item.reason || '—']]) {
            element('dt', label, facts);
            element('dd', value, facts);
        }
        const actions = workspaceActions(details);
        if (!item.excluded) {
            button('编辑统计记录', actions, () => editStatsRecord(item, filters)).className = 'account-primary';
            button('移出统计', actions, () => changeStatsState(item, filters, false)).className = 'workspace-danger';
        }
        if (item.excluded || item.source === 'adjusted') button(item.source === 'manual' ? '恢复计入' : '恢复原始数据', actions, () => changeStatsState(item, filters, true));
    }

    function editStatsRecord(item, filters) {
        startPanel('admin-edit', item ? '编辑统计记录' : '新增统计记录', '仅用于汇总和检索，不会修改玩家原始对局、存档或游客统计。');
        const form = element('form', '', body);
        form.className = 'workspace-sheet workspace-form';
        const grid = workspaceGrid(form);
        const shifted = item ? new Date(Date.parse(item.started_at) + 8 * 3600000).toISOString().slice(0, 23) : bjDate(0) + 'T12:00';
        const when = field(grid, '开局时间（北京时间）', 'started_at', 'datetime-local', shifted);
        when.step = 'any';
        const version = field(grid, '游戏版本', 'game_version', 'text', item?.game_version || buildVersion);
        version.maxLength = 80;
        version.pattern = '[a-zA-Z0-9_.:\\-]+';
        options(grid, '角色', 'character_id', characters, item?.character_id || 'P01');
        options(grid, '难度', 'difficulty', difficulties, item?.difficulty || 'normal');
        options(grid, '首战完成', 'first_battle', {'0': '否', '1': '是'}, item?.first_battle ? '1' : '0');
        options(grid, '整局结算', 'finished', {'0': '否', '1': '是'}, item?.finished ? '1' : '0');
        const reason = field(form, '操作理由（必填）', 'reason');
        reason.maxLength = 500;
        const actions = workspaceActions(form);
        button('取消', actions, () => item ? showStatsRecord(item.record_id, filters) : statsWorkspace('records', filters));
        formSubmit(form, item ? '保存修正' : '新增记录', async values => {
            const data = {...values, started_at: values.started_at + '+08:00', first_battle: values.first_battle === '1', finished: values.finished === '1'};
            if (item) data.revision = item.revision;
            const saved = await request(statsRoute(item?.record_id), item ? 'PATCH' : 'POST', data);
            await showStatsRecord(saved.record_id, filters, item ? '统计修正已保存。' : '记录已新增；若不在当前筛选范围内，请调整筛选。');
        }, actions);
    }

    function changeStatsState(item, filters, restore) {
        const label = restore ? (item.source === 'manual' ? '恢复计入' : '恢复原始数据') : '移出统计';
        startPanel('admin-confirm', label, restore ? '记录将重新计入统计。自动记录的人工修正也会同时清除。' : '这条记录将不再计入汇总。可在「已移出」中找到并恢复，玩家原始对局不会删除。');
        const form = element('form', '', body);
        form.className = 'workspace-sheet workspace-form';
        element('p', `${item.game_version} · ${bjTime(item.started_at)} · ${item.record_id}`, form).className = 'feedback-text';
        field(form, '操作理由（必填）', 'reason').maxLength = 500;
        const actions = workspaceActions(form);
        button('取消', actions, () => showStatsRecord(item.record_id, filters));
        formSubmit(form, '确认' + label, async values => {
            await request(statsRoute(item.record_id) + (restore ? '/restore' : ''), restore ? 'POST' : 'DELETE', {...values, revision: item.revision});
            await showStatsRecord(item.record_id, filters, restore ? '已恢复。' : '已移出统计。');
        }, actions);
    }


    async function downloadReport(kind, query, trigger, statusLine) {
        trigger.disabled = true;
        statusLine.textContent = '正在生成 XLSX…';
        try {
            const response = await fetch(api + '/admin/exports/' + kind + '?' + query, {
                headers: {'X-Kapai-Account': account.user_id}, cache: 'no-store', credentials: 'same-origin',
                signal: AbortSignal.timeout(30000),
            });
            if (!response.ok) throw new Error((await response.json()).detail);
            if (!response.headers.get('content-type')?.startsWith('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'))
                throw new Error('export_invalid_file');
            const blob = await response.blob();
            if (!trigger.isConnected || !dialog.open) return;
            const url = URL.createObjectURL(blob);
            const link = element('a', '', document.body);
            link.href = url;
            link.download = response.headers.get('content-disposition')?.match(/filename="(kapai-[a-z]+-[\d-]+\.xlsx)"/)?.[1] || 'kapai-export.xlsx';
            link.click();
            link.remove();
            setTimeout(() => URL.revokeObjectURL(url), 30000);
            statusLine.textContent = 'XLSX 已生成，请查看浏览器下载列表。';
        } catch (error) {
            statusLine.textContent = statuses[error.message] || '暂时无法导出，请稍后重试。';
        } finally {
            trigger.disabled = false;
        }
    }

    function exportControls(parent, kind, query) {
        const params = new URLSearchParams(query);
        params.delete('offset');
        const actions = workspaceActions(parent);
        actions.classList.add('workspace-export');
        const trigger = button('导出 XLSX', actions, () => downloadReport(kind, params, trigger, note));
        const note = element('small', '导出当前查询条件下的全部结果，最多 5000 行。', actions);
        note.setAttribute('role', 'status');
    }

    const playerDataRoute = id => '/admin/data/players' + (id ? '/' + encodeURIComponent(id) : '');

    async function showDataMaintenance(filters = {q: '', offset: 0}, back = showStats, message = '') {
        startPanel('admin-data', '数据库维护', '修改普通玩家的显示昵称。不会修改登录名、权限、密码或存档。');
        const nav = workspaceActions(body);
        button('← 返回管理页面', nav, back);
        const form = element('form', '', body);
        form.className = 'workspace-form workspace-filters';
        optional(form, '搜索玩家', 'q', filters.q, 100, 'search', '昵称、登录名或账号编号');
        const actions = workspaceActions(form);
        button('清空筛选', actions, () => showDataMaintenance({q: '', offset: 0}, back));
        const results = workspaceResult(body);
        formSubmit(form, '查询玩家', values => render({...values, offset: 0}), actions);

        async function render(state, banner = '') {
            results.replaceChildren();
            if (banner) resultText(results, banner);
            const progress = resultText(results, '正在读取玩家…');
            let data;
            try { data = await request(playerDataRoute() + '?' + new URLSearchParams(state)); }
            catch (error) {
                progress.textContent = '暂时无法读取玩家，请重试。';
                if (results.isConnected && dialog.open) throw error;
                return;
            }
            if (!progress.isConnected || !dialog.open) return;
            progress.textContent = data.items.length ? `共 ${data.total} 个玩家 · 第 ${1 + Math.floor(state.offset / 20)} 页` : '没有符合条件的普通玩家。';
            const list = element('div', '', results);
            list.className = 'feedback-list';
            for (const item of data.items) {
                recordCard(list, item.nickname, `${item.username || '未设置登录名'} · ${item.user_id}`,
                    [['普通玩家', '']], () => showPlayerMaintenance(item.user_id, state, back));
            }
            pager(results, data, state.offset, offset => showDataMaintenance({...state, offset}, back));
        }
        await render(filters, message);
    }

    async function showPlayerMaintenance(id, filters, back, message = '') {
        startPanel('admin-data-detail', '玩家资料', '数据库中的显示昵称会用于账号、反馈和对局管理。');
        button('← 返回数据库维护', workspaceActions(body), () => showDataMaintenance(filters, back));
        const details = workspaceResult(body);
        const progress = resultText(details, '正在读取账号…');
        let item;
        try { item = await request(playerDataRoute(id)); }
        catch (error) {
            progress.textContent = '暂时无法读取账号。';
            if (details.isConnected && dialog.open) throw error;
            return;
        }
        if (!details.isConnected || !dialog.open) return;
        details.replaceChildren();
        if (message) resultText(details, message);
        const profile = element('section', '', details);
        profile.className = 'workspace-sheet';
        element('h3', item.nickname, profile);
        const dl = element('dl', '', profile);
        dl.className = 'workspace-facts';
        for (const [key, value] of [['账号编号', id], ['登录名', item.username || '未设置'], ['注册时间（北京时间）', bjTime(item.created_at)]]) {
            element('dt', key, dl);
            element('dd', value, dl);
        }
        const actions = workspaceActions(details);
        button('修改显示昵称', actions, () => editPlayerNickname(item, filters, back)).className = 'account-primary';
        if (item.can_restore) button('撤回上一笔修改', actions, () => confirmPlayerNickname(item, filters, back));
        const history = element('section', '', details);
        history.className = 'workspace-sheet';
        element('h3', '最近修改记录', history);
        if (!item.history.length) element('p', '还没有修改记录。', history);
        for (const change of item.history) {
            const row = element('article', '', history);
            row.className = 'workspace-change';
            element('strong', `${change.old_nickname} → ${change.new_nickname}`, row);
            element('p', change.reason, row).className = 'feedback-text';
            element('small', bjTime(change.changed_at) + '（北京时间）', row);
        }
    }

    function editPlayerNickname(item, filters, back) {
        startPanel('admin-data-edit', '修改显示昵称', '登录名保持不变；确认前可核对新旧昵称。');
        const form = element('form', '', body);
        form.className = 'workspace-sheet workspace-form';
        element('p', '当前昵称：' + item.nickname, form).className = 'feedback-text';
        const nickname = field(form, '新显示昵称', 'nickname', 'text', item.nickname);
        nickname.maxLength = 40;
        counter(nickname);
        const actions = workspaceActions(form);
        button('取消', actions, () => showPlayerMaintenance(item.user_id, filters, back));
        formSubmit(form, '下一步', values => {
            const name = values.nickname.trim();
            if (!name) throw new Error('invalid_input');
            if (name === item.nickname) throw new Error('maintenance_nickname_unchanged');
            confirmPlayerNickname(item, filters, back, name);
        }, actions);
    }

    function confirmPlayerNickname(item, filters, back, newName = null) {
        const restore = newName === null;
        startPanel('admin-data-confirm', restore ? '撤回上一笔修改' : '确认修改显示昵称', '确认后会写入数据库并保留操作记录。');
        const form = element('form', '', body);
        form.className = 'workspace-sheet workspace-form';
        element('p', `昵称：${item.nickname} → ${newName ?? item.history[0].old_nickname}`, form).className = 'feedback-text';
        field(form, '操作原因（必填）', 'reason').maxLength = 500;
        const actions = workspaceActions(form);
        button('取消', actions, () => showPlayerMaintenance(item.user_id, filters, back));
        formSubmit(form, restore ? '确认撤回' : '确认写入数据库', async values => {
            const route = playerDataRoute(item.user_id) + '/nickname';
            const payload = {reason: values.reason, revision: item.revision, expected_nickname: item.nickname};
            if (!restore) payload.nickname = newName;
            await request(route + (restore ? '/restore' : ''), restore ? 'POST' : 'PATCH', payload);
            await showPlayerMaintenance(item.user_id, filters, back, restore ? '已撤回修改。' : '显示昵称已写入数据库。');
        }, actions);
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
            const loopback = ['localhost', '127.0.0.1', '[::1]'].includes(location.hostname);
            game('tutorial_online', String(!loopback));
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
                else if (section === 'feedback') showFeedback();
                else if (section === 'feedback_admin') {
                    await checkAdminWorkspace();
                    await showFeedbackInbox();
                }
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
