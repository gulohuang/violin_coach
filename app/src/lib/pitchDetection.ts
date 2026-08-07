/**
 * Autocorrelation-based pitch detector.
 *
 * Autocorrelation is used (rather than FFT peak-picking) because a bowed
 * string's fundamental is often weaker than its overtones, which throws off
 * naive spectral peak detection. Autocorrelation finds the lag that best
 * repeats the whole waveform, which tracks the true fundamental more
 * reliably for sustained monophonic tones like a violin note.
 */

const NOTE_NAMES = [
  "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
] as const;

export interface PitchResult {
  frequency: number;
}

export interface NoteMatch {
  midi: number;
  name: string;
  octave: number;
  /** Deviation from the nearest chromatic note, in cents. Negative = flat, positive = sharp. */
  cents: number;
}

/**
 * Detects the fundamental frequency of a monophonic audio buffer via
 * normalized autocorrelation. Returns null when no clear periodicity is
 * found (silence, noise, or a signal too quiet to trust).
 */
export function autoCorrelate(buffer: Float32Array, sampleRate: number): number | null {
  const n = buffer.length;

  let rms = 0;
  for (let i = 0; i < n; i++) rms += buffer[i] * buffer[i];
  rms = Math.sqrt(rms / n);
  if (rms < 0.01) return null;

  // Trim silence at the edges so autocorrelation isn't skewed by leading/trailing quiet.
  let start = 0;
  let end = n - 1;
  const threshold = rms * 0.2;
  while (start < n && Math.abs(buffer[start]) < threshold) start++;
  while (end > start && Math.abs(buffer[end]) < threshold) end--;

  const trimmed = buffer.subarray(start, end + 1);
  const size = trimmed.length;
  if (size < 512) return null;

  const minFreq = 150; // below violin's open G (~196Hz), with margin
  const maxFreq = 3500; // above violin's practical upper range
  const minLag = Math.floor(sampleRate / maxFreq);
  const maxLag = Math.min(Math.floor(sampleRate / minFreq), size - 1);
  if (maxLag <= minLag) return null;

  const correlations = new Float32Array(maxLag + 1);
  for (let lag = minLag; lag <= maxLag; lag++) {
    let sum = 0;
    for (let i = 0; i < size - lag; i++) {
      sum += trimmed[i] * trimmed[i + lag];
    }
    correlations[lag] = sum;
  }

  let bestLag = -1;
  let bestValue = -Infinity;
  for (let lag = minLag; lag <= maxLag; lag++) {
    if (correlations[lag] > bestValue) {
      bestValue = correlations[lag];
      bestLag = lag;
    }
  }
  if (bestLag <= minLag || bestValue <= 0) return null;

  // Parabolic interpolation around the peak for sub-sample lag precision.
  const y0 = correlations[bestLag - 1];
  const y1 = correlations[bestLag];
  const y2 = correlations[bestLag + 1] ?? y1;
  const denom = 2 * (2 * y1 - y0 - y2);
  const shift = denom !== 0 ? (y0 - y2) / denom : 0;
  const refinedLag = bestLag + Math.max(-1, Math.min(1, shift));

  const frequency = sampleRate / refinedLag;
  if (!Number.isFinite(frequency) || frequency < minFreq || frequency > maxFreq) return null;
  return frequency;
}

/** Converts a frequency to the nearest chromatic note, MIDI number, and cents deviation. */
export function frequencyToNote(frequency: number, a4 = 440): NoteMatch {
  const midiFloat = 69 + 12 * Math.log2(frequency / a4);
  const midi = Math.round(midiFloat);
  const cents = Math.round((midiFloat - midi) * 100);
  const name = NOTE_NAMES[((midi % 12) + 12) % 12];
  const octave = Math.floor(midi / 12) - 1;
  return { midi, name, octave, cents };
}

export function midiToFrequency(midi: number, a4 = 440): number {
  return a4 * Math.pow(2, (midi - 69) / 12);
}

export function noteLabel(match: NoteMatch): string {
  return `${match.name}${match.octave}`;
}
