const KapaiWebPack = (() => {
    const cacheName = 'kapai-web-pack-v1';

    async function loadChunk(cache, url, size) {
        try {
            const cached = await cache?.match(url);
            if (cached) {
                const data = await cached.arrayBuffer();
                if (data.byteLength === size) return data;
            }
        } catch {
            // Storage may be disabled or unavailable in this browser.
        }

        const response = await fetch(url, { cache: 'force-cache' });
        if (!response.ok) throw new Error(`下载游戏资源失败（HTTP ${response.status}）。请刷新重试。`);
        const data = await response.arrayBuffer();
        if (data.byteLength !== size) throw new Error('游戏资源下载不完整。请刷新重试。');
        try {
            await cache?.put(url, new Response(data));
        } catch {
            // A quota or storage error must not prevent the game from starting.
        }
        return data;
    }

    async function loadPack(chunks, onProgress) {
        let cache;
        try {
            cache = await window.caches?.open(cacheName);
        } catch {
            // HTTP downloads also work without Cache Storage.
        }

        const total = chunks.reduce((sum, [, size]) => sum + size, 0);
        const pack = new Uint8Array(total);
        let next = 0;
        let offset = 0;
        let loaded = 0;
        async function download() {
            while (next < chunks.length) {
                const [url, size] = chunks[next++];
                const start = offset;
                offset += size;
                pack.set(new Uint8Array(await loadChunk(cache, url, size)), start);
                loaded += size;
                onProgress(loaded, total);
            }
        }
        onProgress(0, total);
        await Promise.all([download(), download(), download()]);
        return { pack, cache };
    }

    async function removeOldChunks(cache, chunks) {
        if (!cache) return;
        const active = new Set(chunks.map(([url]) => new URL(url, document.baseURI).href));
        for (const request of await cache.keys()) {
            if (!active.has(request.url)) await cache.delete(request);
        }
    }

    return {
        async start(engine, config, assets, { onProgress }) {
            // Keep the original pack name inside Godot's virtual filesystem.
            const [, { pack, cache }] = await Promise.all([
                engine.init(assets.engine),
                loadPack(assets.chunks, onProgress),
            ]);
            await engine.preloadFile(pack.buffer, 'index.pck');
            await engine.start({ args: ['--main-pack', 'index.pck', ...config.args] });
            void removeOldChunks(cache, assets.chunks).catch(() => {});
        },
    };
})();
