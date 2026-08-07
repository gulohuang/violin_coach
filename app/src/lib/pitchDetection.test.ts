import { describe, expect, it } from "vitest";
import { autoCorrelate, frequencyToNote, midiToFrequency, noteLabel } from "./pitchDetection";

function generateSineWave(frequency: number, sampleRate: number, seconds: number): Float32Array {
  const n = Math.floor(sampleRate * seconds);
  const buffer = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    buffer[i] = 0.8 * Math.sin((2 * Math.PI * frequency * i) / sampleRate);
  }
  return buffer;
}

describe("autoCorrelate", () => {
  const sampleRate = 44100;

  it("returns null for silence", () => {
    const buffer = new Float32Array(4096);
    expect(autoCorrelate(buffer, sampleRate)).toBeNull();
  });

  it.each([
    ["open G3", 196.0],
    ["open D4", 293.66],
    ["open A4", 440.0],
    ["open E5", 659.25],
    ["G4 (1st finger on D string)", 392.0],
  ])("detects %s (%dHz) within 1%% tolerance", (_label, frequency) => {
    const buffer = generateSineWave(frequency, sampleRate, 0.1);
    const detected = autoCorrelate(buffer, sampleRate);
    expect(detected).not.toBeNull();
    expect(Math.abs(detected! - frequency) / frequency).toBeLessThan(0.01);
  });

  it("ignores a quiet noise floor", () => {
    const buffer = new Float32Array(4096).map(() => (Math.random() - 0.5) * 0.005);
    expect(autoCorrelate(buffer, sampleRate)).toBeNull();
  });
});

describe("frequencyToNote", () => {
  it("identifies A4 as exactly in tune at 440Hz", () => {
    const match = frequencyToNote(440);
    expect(match.name).toBe("A");
    expect(match.octave).toBe(4);
    expect(match.cents).toBe(0);
  });

  it("identifies a note 20 cents sharp", () => {
    const sharpFreq = 440 * Math.pow(2, 20 / 1200);
    const match = frequencyToNote(sharpFreq);
    expect(match.name).toBe("A");
    expect(match.cents).toBe(20);
  });

  it("identifies a note 20 cents flat", () => {
    const flatFreq = 440 * Math.pow(2, -20 / 1200);
    const match = frequencyToNote(flatFreq);
    expect(match.name).toBe("A");
    expect(match.cents).toBe(-20);
  });

  it("round-trips through midiToFrequency", () => {
    const match = frequencyToNote(midiToFrequency(69));
    expect(noteLabel(match)).toBe("A4");
  });

  it("labels violin open strings correctly", () => {
    expect(noteLabel(frequencyToNote(196.0))).toBe("G3");
    expect(noteLabel(frequencyToNote(293.66))).toBe("D4");
    expect(noteLabel(frequencyToNote(440.0))).toBe("A4");
    expect(noteLabel(frequencyToNote(659.25))).toBe("E5");
  });
});
