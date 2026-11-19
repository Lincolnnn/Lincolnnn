// =====================================================================================================================
// LIVEVIEW — diffusion de l'écran du JEU vers les dispatchers du MDC Web, en vidéo WebRTC (écrit de zéro).
//
//  1. CAPTURE : le rendu du jeu est lu comme une texture WebGL (séquence de paramètres reconnue par le navigateur
//     intégré de FiveM : la texture devient l'image du jeu, sans le MDC ni les autres interfaces) et dessinée à
//     chaque image dans un canevas hors écran (taille plafonnée, proportions de l'écran gardées).
//  2. PISTE VIDÉO : canvas.captureStream(i/s) ; indice « motion » (le navigateur privilégie la fluidité).
//  3. ENVOI : une RTCPeerConnection par dispatcher (« liaison »), en émission seule. Offre, réponse et candidats ICE
//     passent par le site (Socket.IO, espace /live, jeton de diffusion donné par le serveur) ; la vidéo va DIRECTEMENT
//     au navigateur du dispatcher (ou par un serveur TURN). Codec préféré : H.264 (sinon VP8 / VP9).
//  4. QUALITÉ : mosaïque (image réduite, cadence et débit plus bas) ou agrandi (pleine taille, 30 i/s) : changé en
//     direct sur la liaison concernée (setParameters), sans renégociation ; « maintain-framerate » : en cas de réseau
//     faible, la netteté baisse avant la fluidité.
// Rien ne tourne hors LiveView : la capture, le canevas et les connexions n'existent que pendant une diffusion.
// =====================================================================================================================
(() => {
    'use strict';

    const live = {
        token: null, url: null, socket: null, cfg: null, starting: null,
        canvas: null, gl: null, raf: 0, stream: null, track: null, lastDraw: 0, frames: [], width: 0, height: 0,
        peers: new Map(), // peerId -> { pc, session, mode, pending: [], restarted: false, statsTimer }
        stopTimer: null,
    };

    // ---------------------------------------------------------------------------------------------- socket.io (vendor)
    let ioLoading = null;
    function loadIo() {
        if (window.io) return Promise.resolve(window.io);
        if (!ioLoading) {
            ioLoading = new Promise((resolve, reject) => {
                const s = document.createElement('script');
                s.src = 'vendor/socket.io.min.js';
                s.onload = () => (window.io ? resolve(window.io) : reject(new Error('socket.io')));
                s.onerror = () => { ioLoading = null; reject(new Error('socket.io')); };
                document.head.appendChild(s);
            });
        }
        return ioLoading;
    }

    // ---------------------------------------------------------------------------------------------- capture du jeu
    const VERTEX = 'attribute vec2 p; attribute vec2 t; varying vec2 uv; void main() { gl_Position = vec4(p, 0.0, 1.0); uv = t; }';
    const FRAGMENT = 'precision mediump float; varying vec2 uv; uniform sampler2D tex; void main() { gl_FragColor = texture2D(tex, uv); }';

    function shader(gl, type, src) {
        const s = gl.createShader(type);
        gl.shaderSource(s, src);
        gl.compileShader(s);
        if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) throw new Error(gl.getShaderInfoLog(s) || 'shader');
        return s;
    }

    /** Texture liée au rendu du jeu : séquence de paramètres « magique » reconnue par le navigateur de FiveM */
    function gameTexture(gl) {
        const tex = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, tex);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 0, 255]));
        gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.MIRRORED_REPEAT);
        gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        return tex;
    }

    function captureSize() {
        const maxW = (live.cfg && live.cfg.maxWidth) || 1280;
        const maxH = (live.cfg && live.cfg.maxHeight) || 720;
        const w = Math.max(320, window.innerWidth || 1920);
        const h = Math.max(180, window.innerHeight || 1080);
        const k = Math.min(1, maxW / w, maxH / h);
        // dimensions paires (exigées par les encodeurs H.264)
        return { width: Math.floor((w * k) / 2) * 2, height: Math.floor((h * k) / 2) * 2 };
    }

    function startCapture() {
        if (live.stream) return live.stream;
        const canvas = document.createElement('canvas');
        const { width, height } = captureSize();
        canvas.width = width; canvas.height = height;
        const gl = canvas.getContext('webgl', { alpha: false, antialias: false, depth: false, stencil: false, desynchronized: true,
            preserveDrawingBuffer: false, powerPreference: 'high-performance' });
        if (!gl) throw new Error('WebGL indisponible');
        const program = gl.createProgram();
        gl.attachShader(program, shader(gl, gl.VERTEX_SHADER, VERTEX));
        gl.attachShader(program, shader(gl, gl.FRAGMENT_SHADER, FRAGMENT));
        gl.linkProgram(program);
        gl.useProgram(program);
        const quad = (name, data) => {
            const buf = gl.createBuffer();
            gl.bindBuffer(gl.ARRAY_BUFFER, buf);
            gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(data), gl.STATIC_DRAW);
            const loc = gl.getAttribLocation(program, name);
            gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
            gl.enableVertexAttribArray(loc);
        };
        quad('p', [-1, -1, 1, -1, -1, 1, 1, 1]);
        quad('t', [0, 0, 1, 0, 0, 1, 1, 1]);
        gl.activeTexture(gl.TEXTURE0);
        gameTexture(gl);
        gl.uniform1i(gl.getUniformLocation(program, 'tex'), 0);
        gl.viewport(0, 0, width, height);
        live.canvas = canvas; live.gl = gl; live.width = width; live.height = height;

        const fps = (live.cfg && live.cfg.fps) || 30;
        const minGap = 1000 / fps - 2;
        const draw = (now) => {
            if (!live.gl) return;
            live.raf = requestAnimationFrame(draw);
            if (now - live.lastDraw < minGap) return; // pas plus d'images que la cadence demandée
            live.lastDraw = now;
            gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
            live.frames.push(now);
            while (live.frames.length && now - live.frames[0] > 2000) live.frames.shift();
        };
        live.raf = requestAnimationFrame(draw);
        live.stream = canvas.captureStream(fps);
        live.track = live.stream.getVideoTracks()[0];
        if (live.track && 'contentHint' in live.track) live.track.contentHint = 'motion';
        return live.stream;
    }

    function stopCapture() {
        cancelAnimationFrame(live.raf);
        live.raf = 0;
        if (live.stream) live.stream.getTracks().forEach((t) => t.stop());
        if (live.gl) { const ext = live.gl.getExtension('WEBGL_lose_context'); if (ext) ext.loseContext(); }
        live.stream = null; live.track = null; live.gl = null; live.canvas = null; live.frames = [];
    }

    window.addEventListener('resize', () => { // résolution du jeu changée : canevas adapté (la piste suit)
        if (!live.canvas || !live.gl) return;
        const { width, height } = captureSize();
        if (width === live.width && height === live.height) return;
        live.canvas.width = width; live.canvas.height = height;
        live.gl.viewport(0, 0, width, height);
        live.width = width; live.height = height;
    });

    const captureFps = () => (live.frames.length > 1 ? (live.frames.length - 1) / ((live.frames[live.frames.length - 1] - live.frames[0]) / 1000) : 0);

    // ---------------------------------------------------------------------------------------------- WebRTC
    function modeParams(mode) {
        const m = (live.cfg && live.cfg.modes && live.cfg.modes[mode]) || { scale: mode === 'focus' ? 1 : 2, fps: mode === 'focus' ? 30 : 20, kbps: mode === 'focus' ? 3000 : 700 };
        return { scaleResolutionDownBy: Math.max(1, Number(m.scale) || 1), maxFramerate: Math.max(5, Number(m.fps) || 30), maxBitrate: Math.max(150, Number(m.kbps) || 1000) * 1000 };
    }

    function preferCodec(transceiver) {
        if (!transceiver.setCodecPreferences || !window.RTCRtpSender || !RTCRtpSender.getCapabilities) return;
        const caps = RTCRtpSender.getCapabilities('video');
        if (!caps) return;
        const want = `video/${String((live.cfg && live.cfg.codec) || 'h264').toUpperCase()}`;
        const score = (c) => {
            const mime = c.mimeType.toUpperCase();
            if (mime === want) return mime === 'VIDEO/H264' && /packetization-mode=1/.test(c.sdpFmtpLine || '') ? 0 : 1;
            if (/VIDEO\/(RTX|RED|ULPFEC|FLEXFEC)/.test(mime)) return 3;
            return 2;
        };
        try { transceiver.setCodecPreferences([...caps.codecs].sort((a, b) => score(a) - score(b))); } catch (e) { /* codec indisponible : ordre par défaut */ }
    }

    async function applyMode(peer) {
        const sender = peer.transceiver && peer.transceiver.sender;
        if (!sender) return;
        const params = sender.getParameters();
        if (!params.encodings || !params.encodings.length) params.encodings = [{}];
        Object.assign(params.encodings[0], modeParams(peer.mode));
        params.degradationPreference = 'maintain-framerate';
        await sender.setParameters(params).catch(() => {});
    }

    const signal = (data) => { if (live.socket && live.socket.connected) live.socket.emit('signal', data); };

    async function negotiate(peerId, iceRestart) {
        const peer = live.peers.get(peerId);
        if (!peer) return;
        try {
            const offer = await peer.pc.createOffer(iceRestart ? { iceRestart: true } : undefined);
            await peer.pc.setLocalDescription(offer);
            signal({ peerId, session: peer.session, description: { type: 'offer', sdp: peer.pc.localDescription.sdp } });
        } catch (e) {
            closePeer(peerId);
        }
    }

    function openPeer(peerId, mode) {
        const existing = live.peers.get(peerId);
        if (existing && ['new', 'connecting', 'connected'].includes(existing.pc.connectionState)) { // liaison déjà active
            if (existing.mode !== mode) { existing.mode = mode; applyMode(existing); }
            return;
        }
        if (existing) closePeer(peerId);
        const stream = startCapture();
        const pc = new RTCPeerConnection({
            iceServers: (live.cfg && live.cfg.iceServers) || [],
            iceTransportPolicy: live.cfg && live.cfg.relayOnly ? 'relay' : 'all',
            bundlePolicy: 'max-bundle',
        });
        const transceiver = pc.addTransceiver(live.track, { direction: 'sendonly', streams: [stream], sendEncodings: [modeParams(mode)] });
        preferCodec(transceiver);
        const peer = { pc, transceiver, mode, session: Math.random().toString(36).slice(2, 12), pending: [], restarted: false, statsTimer: null };
        live.peers.set(peerId, peer);
        pc.onicecandidate = (e) => signal({ peerId, session: peer.session, candidate: e.candidate ? e.candidate.toJSON() : null });
        pc.onconnectionstatechange = () => {
            if (live.peers.get(peerId) !== peer) return;
            if (pc.connectionState === 'connected') { peer.restarted = false; applyMode(peer); }
            if (pc.connectionState === 'failed') {
                if (!peer.restarted) { peer.restarted = true; negotiate(peerId, true); } else closePeer(peerId);
            }
        };
        // cadence réellement capturée (affichée chez le dispatcher), toutes les 2 s
        peer.statsTimer = setInterval(() => signal({ peerId, session: peer.session, stats: { fps: Math.round(captureFps() * 10) / 10, width: live.width, height: live.height } }), 2000);
        negotiate(peerId, false);
    }

    function closePeer(peerId) {
        const peer = live.peers.get(peerId);
        if (!peer) return;
        live.peers.delete(peerId);
        clearInterval(peer.statsTimer);
        try { peer.pc.close(); } catch (e) { /* déjà fermée */ }
        if (!live.peers.size) scheduleIdleStop();
    }

    // aucune liaison pendant 20 s : capture arrêtée (le GPU ne travaille plus) ; une nouvelle liaison la relance
    function scheduleIdleStop() {
        clearTimeout(live.stopTimer);
        live.stopTimer = setTimeout(() => { if (!live.peers.size) stopCapture(); }, 20000);
    }

    async function onSignal(msg) {
        const peer = msg && live.peers.get(msg.peerId);
        if (!peer) return;
        try {
            if (msg.description && msg.description.type === 'answer') {
                await peer.pc.setRemoteDescription(msg.description);
                for (const c of peer.pending.splice(0)) await peer.pc.addIceCandidate(c).catch(() => {});
            } else if (msg.candidate !== undefined) {
                if (!peer.pc.remoteDescription) peer.pending.push(msg.candidate);
                else await peer.pc.addIceCandidate(msg.candidate).catch(() => {});
            } else if (msg.restart) {
                negotiate(msg.peerId, true);
            }
        } catch (e) {
            closePeer(msg.peerId);
        }
    }

    // ---------------------------------------------------------------------------------------------- démarrage / arrêt
    async function start(order) {
        if (!order || !order.url || !order.token) return;
        if (live.token === order.token && (live.socket || live.starting)) return; // renouvellement : rien à refaire
        stop('nouvelle diffusion');
        live.token = order.token; live.url = order.url;
        const token = order.token;
        live.starting = loadIo().then((io) => {
            if (live.token !== token) return;
            const socket = io(`${order.url}/live`, { auth: { token }, transports: ['websocket'], reconnectionAttempts: 8, reconnectionDelayMax: 4000, timeout: 8000 });
            live.socket = socket;
            socket.on('config', (cfg) => { live.cfg = cfg || {}; });
            socket.on('peer', (d) => { if (d && d.peerId) { clearTimeout(live.stopTimer); openPeer(String(d.peerId), d.mode === 'focus' ? 'focus' : 'grid'); } });
            socket.on('peer:mode', (d) => { const p = d && live.peers.get(d.peerId); if (p) { p.mode = d.mode === 'focus' ? 'focus' : 'grid'; applyMode(p); } });
            socket.on('peer:close', (d) => { if (d) closePeer(d.peerId); });
            socket.on('signal', onSignal);
            socket.on('stop', () => stop('arrêt demandé par le site'));
            socket.on('connect_error', (err) => { if (err && err.message === 'refused') stop('jeton refusé'); });
            socket.io.on('reconnect_failed', () => stop('site injoignable'));
        }).catch(() => { live.token = null; }).finally(() => { live.starting = null; });
    }

    function stop() {
        clearTimeout(live.stopTimer);
        for (const id of [...live.peers.keys()]) closePeer(id);
        clearTimeout(live.stopTimer);
        stopCapture();
        if (live.socket) { live.socket.removeAllListeners(); live.socket.disconnect(); }
        live.socket = null; live.token = null; live.url = null; live.cfg = null;
    }

    window.MDCLive = { start, stop, status: () => ({ token: !!live.token, peers: live.peers.size, fps: captureFps(), width: live.width, height: live.height }) };
})();
