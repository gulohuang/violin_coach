import type { OpenSheetMusicDisplay } from "opensheetmusicdisplay";
import { frequencyToNote } from "./pitchDetection";

export interface ScoreNote {
  /** MIDI note number (concert pitch, A4 = 69 = 440Hz), read from the MusicXML pitch. */
  midi: number;
  /** Duration in quarter-note beats. */
  beats: number;
}

/**
 * Walks every note OSMD parsed out of the loaded MusicXML, in the same
 * left-to-right, top-to-bottom order the cursor visits them. Rests are
 * skipped; for chords (multiple simultaneous notes) we take the first
 * sounding pitch, since practice/playback here is monophonic (one violin
 * line), matching how a solo player reads a single-staff part.
 *
 * Reading note.Pitch.Frequency (rather than OSMD's internal halfTone
 * numbering) keeps this decoupled from OSMD's internal pitch representation
 * — we only need standard concert-pitch Hz, which we then convert to a MIDI
 * number using this app's own pitch-detection conversion.
 */
export function extractNotes(osmd: OpenSheetMusicDisplay): ScoreNote[] {
  const notes: ScoreNote[] = [];
  const cursor = osmd.cursor;
  cursor.reset();
  while (!cursor.iterator.EndReached) {
    const voiceEntries = cursor.Iterator.CurrentVoiceEntries;
    outer: for (const entry of voiceEntries) {
      for (const note of entry.Notes) {
        if (note.isRest()) continue;
        const midi = frequencyToNote(note.Pitch.Frequency).midi;
        const beats = note.Length.RealValue * 4;
        notes.push({ midi, beats });
        break outer;
      }
    }
    cursor.next();
  }
  cursor.reset();
  return notes;
}

/**
 * Keeps OSMD's visual cursor and a plain note index in lockstep. Anything
 * that wants to move "forward one note" — the auto-player or the practice
 * mode's correct-note detector — goes through `advance()` so the highlighted
 * cursor position and "what note are we expecting" can never drift apart.
 */
export class ScoreCursorController {
  readonly notes: ScoreNote[];
  private osmd: OpenSheetMusicDisplay;
  index = -1;

  constructor(osmd: OpenSheetMusicDisplay) {
    this.osmd = osmd;
    this.notes = extractNotes(osmd);
  }

  get length(): number {
    return this.notes.length;
  }

  get current(): ScoreNote | null {
    return this.index >= 0 && this.index < this.notes.length ? this.notes[this.index] : null;
  }

  get done(): boolean {
    return this.index >= this.notes.length - 1 && this.notes.length > 0;
  }

  reset(): void {
    this.osmd.cursor.reset();
    this.osmd.cursor.show();
    this.index = -1;
  }

  /** Moves both the visual cursor and the note index forward by one note. */
  advance(): void {
    if (this.index >= this.notes.length - 1) return;
    if (this.index >= 0) this.osmd.cursor.next();
    this.index += 1;
  }

  hide(): void {
    this.osmd.cursor.hide();
  }
}
