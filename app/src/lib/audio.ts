import { midiToFrequency } from "./pitchDetection";

let sharedContext: AudioContext | null = null;

export function getAudioContext(): AudioContext {
  if (!sharedContext || sharedContext.state === "closed") {
    sharedContext = new AudioContext();
  }
  return sharedContext;
}

export async function ensureAudioReady(): Promise<AudioContext> {
  const context = getAudioContext();
  if (context.state === "suspended") await context.resume();
  return context;
}

/**
 * Plays a single note as a bowed-string-ish tone: a few harmonics with a
 * soft attack and decay, so it reads as a pitch rather than a flat beep.
 * There's no sampled violin audio bundled with this app (keeps it dependency-
 * free and lightweight) — this synth stands in for it.
 */
export async function playTone(midi: number, seconds: number, a4 = 440): Promise<void> {
  const context = await ensureAudioReady();
  const now = context.currentTime;
  const frequency = midiToFrequency(midi, a4);

  const master = context.createGain();
  master.connect(context.destination);

  const attack = 0.015;
  const release = Math.min(0.12, seconds * 0.3);
  master.gain.setValueAtTime(0.0001, now);
  master.gain.exponentialRampToValueAtTime(0.5, now + attack);
  master.gain.setValueAtTime(0.5, Math.max(now + attack, now + seconds - release));
  master.gain.exponentialRampToValueAtTime(0.0001, now + seconds);

  const harmonics = [
    { multiplier: 1, gain: 1 },
    { multiplier: 2, gain: 0.35 },
    { multiplier: 3, gain: 0.15 },
    { multiplier: 4, gain: 0.08 },
  ];
  for (const { multiplier, gain } of harmonics) {
    const osc = context.createOscillator();
    const oscGain = context.createGain();
    osc.type = multiplier === 1 ? "sawtooth" : "sine";
    osc.frequency.value = frequency * multiplier;
    oscGain.gain.value = gain;
    osc.connect(oscGain).connect(master);
    osc.start(now);
    osc.stop(now + seconds + 0.05);
  }
}

export function scheduleClick(context: AudioContext, when: number, accent = false): void {
  const time = Math.max(when, context.currentTime);
  const osc = context.createOscillator();
  const gain = context.createGain();
  osc.frequency.value = accent ? 1200 : 900;
  osc.type = "square";
  gain.gain.setValueAtTime(0.12, time);
  gain.gain.exponentialRampToValueAtTime(0.0001, time + 0.05);
  osc.connect(gain).connect(context.destination);
  osc.start(time);
  osc.stop(time + 0.06);
}
