// YouTube cast for Room: the Surface shows up as "Room" in the YouTube app's Cast menu (same Wi-Fi, found over DIAL),
// like a TV. Casting plays the video full screen in mpv (which fetches it with yt-dlp — separate picture and sound
// streams, hardware decoding); when casting stops, mpv closes and the panel is back. Controls stay on the phone:
// pause, seek, next, volume.
//
// yt-cast-receiver (github.com/patrickkfkan/yt-cast-receiver) talks to the YouTube app; MpvPlayer below plays.
import YouTubeCastReceiver, { Player, PLAYER_STATUSES } from 'yt-cast-receiver';
import { spawn } from 'node:child_process';
import net from 'node:net';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';

const NAME = process.env.ROOM_CAST_NAME || 'Room';
const SOCK = path.join(os.tmpdir(), `room-cast-mpv-${process.getuid()}.sock`);
const log = (...a) => console.log('[cast]', ...a);

class MpvPlayer extends Player {
  constructor() {
    super();
    this.mpv = null;          // the running mpv (only while something's cast)
    this.conn = null;         // its JSON IPC socket
    this.reqId = 0;
    this.waiting = new Map();
    this.vol = { level: 80, muted: false };
    this.stopping = false;
  }

  // ---------------------------------------------------------------- mpv, started on the first video
  async ensureMpv() {
    if (this.mpv && this.conn) return true;
    try { fs.unlinkSync(SOCK); } catch {}
    this.stopping = false;
    this.mpv = spawn('mpv', [
      '--idle=yes', '--fs', '--no-terminal', '--force-window=yes', '--keep-open=no',
      '--hwdec=auto-safe', '--osd-level=1', '--cursor-autohide=always', '--background-color=#000000',
      `--volume=${this.vol.level}`, `--mute=${this.vol.muted ? 'yes' : 'no'}`,
      '--title=Room · YouTube', '--wayland-app-id=room-cast',
      '--ytdl-format=bestvideo[height<=?1080][vcodec^=avc1]+bestaudio/bestvideo[height<=?1080]+bestaudio/best',
      `--input-ipc-server=${SOCK}`,
    ], { stdio: ['ignore', 'ignore', 'pipe'] });
    this.mpv.stderr.on('data', (d) => process.stderr.write(d));
    this.mpv.on('exit', (code) => {
      log('mpv closed', code ?? '');
      this.mpv = null; this.conn = null;
      if (!this.stopping && this.status !== PLAYER_STATUSES.STOPPED && this.status !== PLAYER_STATUSES.IDLE) {
        this.notifyExternalStateChange(PLAYER_STATUSES.STOPPED).catch(() => {});
      }
    });
    for (let i = 0; i < 50 && !fs.existsSync(SOCK); i++) await new Promise((r) => setTimeout(r, 100));
    return await new Promise((resolve) => {
      const c = net.createConnection(SOCK);
      c.on('connect', () => { this.conn = c; this.listen(c); resolve(true); });
      c.on('error', (e) => { log('mpv socket', e.message); resolve(false); });
    });
  }

  listen(c) {
    let buf = '';
    c.on('data', (d) => {
      buf += d.toString();
      let i;
      while ((i = buf.indexOf('\n')) >= 0) {
        const line = buf.slice(0, i); buf = buf.slice(i + 1);
        let m; try { m = JSON.parse(line); } catch { continue; }
        if (m.request_id && this.waiting.has(m.request_id)) {
          this.waiting.get(m.request_id)(m); this.waiting.delete(m.request_id);
        } else if (m.event === 'end-file' && m.reason === 'eof') {
          // the video finished: the next one in the queue (or stop, at the end)
          (async () => {
            await this.pause().catch(() => {});
            if (!(await this.next().catch(() => false))) await this.stop().catch(() => {});
          })();
        } else if (m.event === 'end-file' && m.reason === 'error') {
          log('mpv could not play it', m.file_error || '');
          this.notifyExternalStateChange(PLAYER_STATUSES.STOPPED).catch(() => {});
        }
      }
    });
  }

  cmd(...command) {
    if (!this.conn) return Promise.resolve({ error: 'no mpv' });
    const id = ++this.reqId;
    return new Promise((resolve) => {
      const t = setTimeout(() => { this.waiting.delete(id); resolve({ error: 'timeout' }); }, 3000);
      this.waiting.set(id, (m) => { clearTimeout(t); resolve(m); });
      this.conn.write(JSON.stringify({ command, request_id: id }) + '\n');
    });
  }

  async prop(name) {
    const r = await this.cmd('get_property', name);
    return r.error === 'success' ? r.data : undefined;
  }

  // ---------------------------------------------------------------- what the YouTube app asks for
  async doPlay(video, position) {
    log('play', video.id, position ? `from ${Math.round(position)} s` : '');
    if (!(await this.ensureMpv())) return false;
    const opts = position > 0 ? `start=${position}` : '';
    const r = await this.cmd('loadfile', `https://www.youtube.com/watch?v=${video.id}`, 'replace', 0, opts);
    await this.cmd('set_property', 'pause', false);
    return r.error === 'success';
  }
  async doPause() { return (await this.cmd('set_property', 'pause', true)).error === 'success'; }
  async doResume() { return (await this.cmd('set_property', 'pause', false)).error === 'success'; }
  async doStop() {
    this.stopping = true;
    if (this.mpv) {
      const p = this.mpv;
      await this.cmd('quit');
      setTimeout(() => { try { p.kill(); } catch {} }, 1500);
    }
    return true;
  }
  async doSeek(position) { return (await this.cmd('seek', position, 'absolute')).error === 'success'; }
  async doSetVolume(volume) {
    this.vol = { level: volume.level, muted: volume.muted };
    if (this.conn) {
      await this.cmd('set_property', 'volume', volume.level);
      await this.cmd('set_property', 'mute', volume.muted);
    }
    return true;
  }
  async doGetVolume() { return this.vol; }
  async doGetPosition() { return (await this.prop('time-pos')) || 0; }
  async doGetDuration() { return (await this.prop('duration')) || 0; }
}

const player = new MpvPlayer();
const receiver = new YouTubeCastReceiver(player, {
  device: { name: NAME, screenName: NAME, brand: 'Room', model: 'Surface' },
  dial: { port: Number(process.env.ROOM_CAST_PORT || 8099) },
});
receiver.on('senderConnect', (s) => log('connected:', s?.name || 'a phone'));
receiver.on('senderDisconnect', (s) => log('disconnected:', s?.name || 'a phone'));
receiver.on('error', (e) => log('error:', e?.message || e));
await receiver.start();
log(`ready — "${NAME}" is in the YouTube app's Cast menu (same Wi-Fi)`);

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, async () => {
    await player.doStop().catch(() => {});
    await receiver.stop().catch(() => {});
    process.exit(0);
  });
}
