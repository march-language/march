// march_audio.mjs — procedural sound-effect synthesis for March programs
// compiled with --target js. Wraps the Web Audio API: short tones, sweeps,
// and filtered noise bursts are synthesized on the fly (no audio files, no
// assets to load or license).

function newHandle() {
  const AC = window.AudioContext || window.webkitAudioContext;
  const ctx = new AC();
  const master = ctx.createGain();
  master.gain.value = 1.0;
  master.connect(ctx.destination);
  return { ctx, master };
}

export function march_audio_create() {
  return newHandle();
}

export function march_audio_resume(handle) {
  if (handle.ctx.state === "suspended") handle.ctx.resume();
}

export function march_audio_set_volume(handle, vol) {
  handle.master.gain.value = vol;
}

// Short attack + exponential decay so a tone doesn't click at its edges and
// reads as a percussive blip rather than a flat, harsh beep.
function envelope(handle, gainNode, duration) {
  const now = handle.ctx.currentTime;
  const g = gainNode.gain;
  g.setValueAtTime(0, now);
  g.linearRampToValueAtTime(0.9, now + 0.008);
  g.exponentialRampToValueAtTime(0.001, now + duration);
}

export function march_audio_beep(handle, freq, duration, wave) {
  const { ctx, master } = handle;
  const osc = ctx.createOscillator();
  const gain = ctx.createGain();
  osc.type = wave;
  osc.frequency.value = freq;
  osc.connect(gain);
  gain.connect(master);
  envelope(handle, gain, duration);
  const now = ctx.currentTime;
  osc.start(now);
  osc.stop(now + duration + 0.02);
}

export function march_audio_sweep(handle, freqFrom, freqTo, duration, wave) {
  const { ctx, master } = handle;
  const osc = ctx.createOscillator();
  const gain = ctx.createGain();
  osc.type = wave;
  const now = ctx.currentTime;
  osc.frequency.setValueAtTime(Math.max(freqFrom, 1), now);
  osc.frequency.exponentialRampToValueAtTime(Math.max(freqTo, 1), now + duration);
  osc.connect(gain);
  gain.connect(master);
  envelope(handle, gain, duration);
  osc.start(now);
  osc.stop(now + duration + 0.02);
}

// A short noise buffer, generated once per context and re-triggered via a
// fresh BufferSource on every call -- cheaper than sampling fresh white
// noise (Math.random per sample) on every burst.
const __noiseBuffers = new WeakMap();

function noiseBuffer(ctx) {
  let buf = __noiseBuffers.get(ctx);
  if (buf === undefined) {
    const seconds = 1.0;
    buf = ctx.createBuffer(1, Math.ceil(ctx.sampleRate * seconds), ctx.sampleRate);
    const data = buf.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = Math.random() * 2 - 1;
    __noiseBuffers.set(ctx, buf);
  }
  return buf;
}

export function march_audio_noise_burst(handle, duration, filterFreq) {
  const { ctx, master } = handle;
  const src = ctx.createBufferSource();
  src.buffer = noiseBuffer(ctx);
  const filter = ctx.createBiquadFilter();
  filter.type = "lowpass";
  filter.frequency.value = filterFreq;
  const gain = ctx.createGain();
  src.connect(filter);
  filter.connect(gain);
  gain.connect(master);
  envelope(handle, gain, duration);
  const now = ctx.currentTime;
  src.start(now);
  src.stop(now + duration + 0.02);
}
