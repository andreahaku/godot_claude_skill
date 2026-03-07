/**
 * ElevenLabs audio provider for Godot Claude Skill.
 *
 * Supports:
 *   - Text-to-Speech (voice lines, narration)
 *   - Sound Effects (one-shot SFX, ambient loops)
 *
 * Uses raw fetch — no SDK dependency.
 */

const ELEVENLABS_BASE = "https://api.elevenlabs.io";

// --- Public Types ---

export interface VoiceSettings {
  stability?: number;
  similarity_boost?: number;
  style?: number;
  use_speaker_boost?: boolean;
}

export interface VoiceLineRequest {
  text: string;
  voice_id: string;
  model?: string;
  language_code?: string;
  voice_settings?: VoiceSettings;
  seed?: number;
  output_format?: string;
}

export interface SfxRequest {
  text: string;
  duration_seconds?: number;
  prompt_influence?: number;
  output_format?: string;
}

export interface AudioGenerationResult {
  audio: Buffer;
  content_type: string;
  provider: "elevenlabs";
  model: string;
  request_id?: string;
}

// --- Provider Implementation ---

function getApiKey(): string {
  const key = process.env.ELEVENLABS_API_KEY || "";
  if (!key) {
    throw new Error(
      "ELEVENLABS_API_KEY environment variable is required. " +
        "Get your key at https://elevenlabs.io/app/settings/api-keys"
    );
  }
  return key;
}

function defaultVoiceModel(): string {
  return process.env.AUDIO_GEN_DEFAULT_VOICE_MODEL || "eleven_flash_v2_5";
}

function defaultSfxModel(): string {
  return process.env.AUDIO_GEN_DEFAULT_SFX_MODEL || "eleven_text_to_sound_v2";
}

function defaultFormat(): string {
  return process.env.AUDIO_GEN_DEFAULT_FORMAT || "mp3_44100_128";
}

/**
 * Generate a voice line using ElevenLabs TTS.
 *
 * POST /v1/text-to-speech/:voice_id
 */
export async function generateVoiceLine(
  req: VoiceLineRequest
): Promise<AudioGenerationResult> {
  const apiKey = getApiKey();
  const model = req.model || defaultVoiceModel();
  const format = req.output_format || defaultFormat();

  const url = `${ELEVENLABS_BASE}/v1/text-to-speech/${req.voice_id}?output_format=${format}`;

  const body: Record<string, unknown> = {
    text: req.text,
    model_id: model,
  };
  if (req.language_code) body.language_code = req.language_code;
  if (req.voice_settings) body.voice_settings = req.voice_settings;
  if (req.seed !== undefined) body.seed = req.seed;

  console.error(
    `[elevenlabs] TTS: voice=${req.voice_id}, model=${model}, text="${req.text.slice(0, 60)}${req.text.length > 60 ? "..." : ""}"`
  );

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "xi-api-key": apiKey,
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(120_000),
  });

  if (!response.ok) {
    const errorText = await response.text();
    const code = mapHttpError(response.status);
    throw new ProviderError(
      `ElevenLabs TTS error (${response.status}): ${errorText}`,
      code
    );
  }

  const audioBuffer = Buffer.from(await response.arrayBuffer());
  const requestId =
    response.headers.get("request-id") ||
    response.headers.get("x-request-id") ||
    undefined;

  return {
    audio: audioBuffer,
    content_type: response.headers.get("content-type") || "audio/mpeg",
    provider: "elevenlabs",
    model,
    request_id: requestId,
  };
}

/**
 * Generate a sound effect using ElevenLabs Sound Generation.
 *
 * POST /v1/sound-generation
 */
export async function generateSfx(
  req: SfxRequest
): Promise<AudioGenerationResult> {
  const apiKey = getApiKey();
  const model = defaultSfxModel();
  const format = req.output_format || defaultFormat();

  const url = `${ELEVENLABS_BASE}/v1/sound-generation`;

  const body: Record<string, unknown> = {
    text: req.text,
    output_format: format,
  };
  if (req.duration_seconds !== undefined)
    body.duration_seconds = req.duration_seconds;
  if (req.prompt_influence !== undefined)
    body.prompt_influence = req.prompt_influence;

  console.error(
    `[elevenlabs] SFX: text="${req.text.slice(0, 60)}${req.text.length > 60 ? "..." : ""}", duration=${req.duration_seconds ?? "auto"}`
  );

  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "xi-api-key": apiKey,
    },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(120_000),
  });

  if (!response.ok) {
    const errorText = await response.text();
    const code = mapHttpError(response.status);
    throw new ProviderError(
      `ElevenLabs SFX error (${response.status}): ${errorText}`,
      code
    );
  }

  const audioBuffer = Buffer.from(await response.arrayBuffer());
  const requestId =
    response.headers.get("request-id") ||
    response.headers.get("x-request-id") ||
    undefined;

  return {
    audio: audioBuffer,
    content_type: response.headers.get("content-type") || "audio/mpeg",
    provider: "elevenlabs",
    model,
    request_id: requestId,
  };
}

/**
 * List available voices from ElevenLabs.
 *
 * GET /v1/voices
 */
export async function listVoices(): Promise<
  Array<{ voice_id: string; name: string; category: string }>
> {
  const apiKey = getApiKey();
  const response = await fetch(`${ELEVENLABS_BASE}/v1/voices`, {
    headers: { "xi-api-key": apiKey },
    signal: AbortSignal.timeout(30_000),
  });

  if (!response.ok) {
    throw new ProviderError(
      `ElevenLabs voices error (${response.status})`,
      mapHttpError(response.status)
    );
  }

  const data = (await response.json()) as {
    voices: Array<{
      voice_id: string;
      name: string;
      category: string;
    }>;
  };

  return data.voices.map((v) => ({
    voice_id: v.voice_id,
    name: v.name,
    category: v.category,
  }));
}

// --- Voice Presets ---

export const VOICE_PRESETS: Record<string, { voice_id: string; name: string; description: string }> = {
  adam: { voice_id: "pNInz6obpgDQGcFmaJgB", name: "Adam", description: "Deep male voice — guards, authority figures" },
  alice: { voice_id: "Xb7hH8MSUJpSbSDYk0k2", name: "Alice", description: "Warm female voice — NPCs, guides" },
  aria: { voice_id: "9BWtsMINqrJLrRacOk9x", name: "Aria", description: "Expressive female voice — narration, companions" },
  bill: { voice_id: "pqHfZKP75CvOlQylNhV4", name: "Bill", description: "Older male voice — mentors, elders" },
  brian: { voice_id: "nPczCjzI2devNBz1zQrb", name: "Brian", description: "Narrator male voice — tutorials, announcements" },
  charlie: { voice_id: "IKne3meq5aSn9XLyUdCD", name: "Charlie", description: "Australian male — casual NPCs" },
  charlotte: { voice_id: "XB0fDUnXU5powFXDhCwa", name: "Charlotte", description: "Elegant female — nobles, merchants" },
  chris: { voice_id: "iP95p4xoKVk53GoZ742B", name: "Chris", description: "Casual male — everyday NPCs" },
  daniel: { voice_id: "onwK4e9ZLuTAKqWW03F9", name: "Daniel", description: "British male — formal, intellectual" },
  eric: { voice_id: "cjVigY5qzO86Huf0OWal", name: "Eric", description: "Friendly male — shopkeepers, allies" },
  george: { voice_id: "JBFqnCBsd6RMkjVDRZzb", name: "George", description: "Warm male — narration, storytelling" },
  jessica: { voice_id: "cgSgspJ2msm6clMCkdEW", name: "Jessica", description: "Young female — adventurers, heroes" },
  laura: { voice_id: "FGY2WhTYpPnrIDTdsKH5", name: "Laura", description: "Soft female — healers, wise figures" },
  lily: { voice_id: "pFZP5JQG7iQjIQuC4Bku", name: "Lily", description: "Light female — children, fairies" },
  roger: { voice_id: "CwhRBWXzGAHq8TQ4Fs17", name: "Roger", description: "Middle-aged male — commanders, bosses" },
  sarah: { voice_id: "EXAVITQu4vr4xnSDxMaL", name: "Sarah", description: "Gentle female — healers, support" },
};

/**
 * Resolve a voice preset name to an ElevenLabs voice ID.
 * If the input matches a preset name, returns the corresponding voice_id.
 * Otherwise, assumes it's a direct voice_id and returns it as-is.
 */
export function resolveVoicePreset(voiceIdOrPreset: string): string {
  if (VOICE_PRESETS[voiceIdOrPreset.toLowerCase()]) {
    return VOICE_PRESETS[voiceIdOrPreset.toLowerCase()].voice_id;
  }
  return voiceIdOrPreset; // assume it's a direct voice_id
}

// --- Error Handling ---

export class ProviderError extends Error {
  code: string;
  constructor(message: string, code: string) {
    super(message);
    this.name = "ProviderError";
    this.code = code;
  }
}

function mapHttpError(status: number): string {
  if (status === 401) return "PROVIDER_AUTH_ERROR";
  if (status === 429) return "PROVIDER_RATE_LIMIT";
  if (status === 422) return "PROVIDER_VALIDATION_ERROR";
  return "PROVIDER_ERROR";
}
