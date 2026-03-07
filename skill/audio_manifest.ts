/**
 * Audio manifest utilities for Godot Claude Skill.
 *
 * Generates and manages .audio.json sidecar files that track
 * provenance, voice settings, and regeneration history for
 * generated audio assets.
 */

import { writeFileSync, existsSync, readFileSync } from "fs";

// --- Types ---

export interface AudioManifest {
  version: number;
  type: "voice_line" | "sfx" | "ambient_loop";
  provider: string;
  created_at: string;
  source: {
    text: string;
    voice_id?: string;
    model: string;
    language_code?: string;
    seed?: number;
    voice_settings?: Record<string, unknown>;
    duration_seconds?: number;
    prompt_influence?: number;
    loop?: boolean;
  };
  output: {
    asset_path: string;
    manifest_path: string;
    format: string;
    mime_type: string;
    requested_asset_path?: string;
    requested_format?: string;
    requested_mime_type?: string;
  };
  godot: {
    bus: string;
    attached_nodes: string[];
    imported: boolean;
  };
  tags: string[];
  usage: {
    license_note: string;
    request_id?: string;
  };
  regeneration: {
    regenerates: string | null;
    history: Array<{
      timestamp: string;
      previous_manifest: string;
    }>;
  };
}

export interface ManifestInput {
  type: "voice_line" | "sfx" | "ambient_loop";
  provider: string;
  text: string;
  model: string;
  asset_path: string;
  format: string;
  mime_type: string;
  requested_asset_path?: string;
  requested_format?: string;
  requested_mime_type?: string;
  voice_id?: string;
  language_code?: string;
  seed?: number;
  voice_settings?: Record<string, unknown>;
  duration_seconds?: number;
  prompt_influence?: number;
  loop?: boolean;
  bus?: string;
  tags?: string[];
  request_id?: string;
}

// --- Helpers ---

/**
 * Derives the manifest file path from the audio file path.
 * e.g., "sword_hit.mp3" -> "sword_hit.audio.json"
 */
export function manifestPathFor(audioFilePath: string): string {
  return audioFilePath.replace(/\.[^.]+$/, ".audio.json");
}

/**
 * Derives the res:// manifest path from the res:// audio path.
 */
export function manifestResPathFor(resPath: string): string {
  return resPath.replace(/\.[^.]+$/, ".audio.json");
}

/**
 * Infer default bus name from audio type.
 */
function defaultBus(type: string): string {
  switch (type) {
    case "voice_line":
      return "Voice";
    case "sfx":
      return "SFX";
    case "ambient_loop":
      return "Ambience";
    default:
      return "Master";
  }
}

// --- Core Functions ---

/**
 * Create a new audio manifest object.
 */
export function createManifest(input: ManifestInput): AudioManifest {
  const manifestPath = manifestResPathFor(input.asset_path);
  return {
    version: 1,
    type: input.type,
    provider: input.provider,
    created_at: new Date().toISOString(),
    source: {
      text: input.text,
      voice_id: input.voice_id,
      model: input.model,
      language_code: input.language_code,
      seed: input.seed,
      voice_settings: input.voice_settings,
      duration_seconds: input.duration_seconds,
      prompt_influence: input.prompt_influence,
      loop: input.loop,
    },
    output: {
      asset_path: input.asset_path,
      manifest_path: manifestPath,
      format: input.format,
      mime_type: input.mime_type,
      requested_asset_path: input.requested_asset_path,
      requested_format: input.requested_format,
      requested_mime_type: input.requested_mime_type,
    },
    godot: {
      bus: input.bus || defaultBus(input.type),
      attached_nodes: [],
      imported: false,
    },
    tags: input.tags || [],
    usage: {
      license_note:
        "Check ElevenLabs plan/usage terms where applicable",
      request_id: input.request_id,
    },
    regeneration: {
      regenerates: null,
      history: [],
    },
  };
}

/**
 * Write manifest JSON to disk as a sidecar file.
 */
export function writeManifest(
  audioFilePath: string,
  manifest: AudioManifest
): string {
  const path = manifestPathFor(audioFilePath);
  writeFileSync(path, JSON.stringify(manifest, null, 2), "utf-8");
  console.error(`Manifest written: ${path}`);
  return path;
}

/**
 * Read an existing manifest from disk, if it exists.
 */
export function readManifest(
  audioFilePath: string
): AudioManifest | null {
  const path = manifestPathFor(audioFilePath);
  if (!existsSync(path)) return null;
  try {
    return JSON.parse(readFileSync(path, "utf-8")) as AudioManifest;
  } catch {
    return null;
  }
}

/**
 * Create a regeneration manifest that links back to the previous one.
 */
export function createRegenerationManifest(
  input: ManifestInput,
  previousManifestPath: string,
  previousManifest: AudioManifest
): AudioManifest {
  const manifest = createManifest(input);
  manifest.regeneration.regenerates = previousManifestPath;
  manifest.regeneration.history = [
    ...previousManifest.regeneration.history,
    {
      timestamp: previousManifest.created_at,
      previous_manifest: previousManifestPath,
    },
  ];
  return manifest;
}
