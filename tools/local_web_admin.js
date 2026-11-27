/* Local-only adapter for the Godot Web bridge, supplied by start_local_web.py. */
(() => {
    'use strict';
    if (location.protocol !== 'http:' || location.hostname !== '127.0.0.1') return;

    let game = null;
    const offline = () => window.alert('当前为本地管理员调试。账号、云存档、对局统计和反馈请在内测站验证。');
    const noop = () => {};
    window.kapaiAccounts = {
        connectGame(callback) {
            game = callback;
            queueMicrotask(() => {
                game('account_features', 'false');
                // No account switch: keep saves in this preview's browser origin only.
                game('account_menu', 'ready', 'false', '本地管理员', '', 'admin');
            });
        },
        confirmPlay() { queueMicrotask(() => game?.('play_confirmed', 'true')); },
        openAccount: offline,
        openSection(section) {
            if (section === 'quit') window.kapaiExitGame?.();
            else offline();
        },
        reply: noop,
        showMenu: noop,
        saved: noop,
        priority: noop,
        record: noop,
        enterGuest: noop,
        exitGuest: noop,
        openPrivacy: noop,
    };
})();
