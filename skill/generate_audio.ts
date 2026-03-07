#!/usr/bin/env bun
/**
 * AI audio generator for Godot projects.
 * Generates voice lines and sound effects using ElevenLabs
 * and saves them to the Godot project's asset directory.
 *
 * Usage:
 *   bun generate_audio.ts voice_line '{"text":"Hello!","voice_id":"adam","output":"res://audio/voice/hello.mp3"}'
 *   bun generate_audio.ts sfx '{"text":"sword clash","output":"res://audio/sfx/sword.mp3"}'
 *   bun generate_audio.ts sfx '{"text":"rain","output":"res://audio/sfx/rain.mp3","normalize":true,"convert_to":"ogg"}'
 *   bun generate_audio.ts list_voices
 *   bun generate_audio.ts list_presets
 *   bun generate_audio.ts inspect '{"file":"res://audio/sfx/sword.mp3"}'
 *   bun generate_audio.ts regenerate '{"file":"res://audio/sfx/sword.mp3"}'
 *
 * Environment variables:
 *   ELEVENLABS_API_KEY           - ElevenLabs API key (required)
 *   AUDIO_GEN_PROVIDER           - "elevenlabs" (default)
 *   AUDIO_GEN_DEFAULT_FORMAT     - Output format (default: mp3_44100_128)
 *   AUDIO_GEN_DEFAULT_VOICE_MODEL - TTS model (default: eleven_flash_v2_5)
 *   AUDIO_GEN_DEFAULT_SFX_MODEL  - SFX model (default: eleven_text_to_sound_v2)
 */

import { mkdirSync, existsSync, unlinkSync, renameSync } from "fs";
import { dirname, resolve } from "path";
import { execSync } from "child_process";
import {
  generateVoiceLine,
  generateSfx,
  listVoices,
  ProviderError,
  resolveVoicePreset,
  VOICE_PRESETS,
} from "./audio_provider_elevenlabs";
import type {
  VoiceLineRequest,
  SfxRequest,
  VoiceSettings,
  AudioGenerationResult,
} from "./audio_provider_elevenlabs";
import {
  createManifest,
  writeManifest,
  readManifest,
  createRegenerationManifest,
  manifestPathFor,
  manifestResPathFor,
} from "./audio_manifest";
import type { AudioManifest, ManifestInput } from "./audio_manifest";

// --- Input Types ---

interface AudioPostProcessOptions {
  convert_to?: string;    // "ogg", "wav" — convert output format
  normalize?: boolean;    // Normalize volume to -3dB peak
  trim_silence?: boolean; // Trim leading/trailing silence
}

interface VoiceLineOptions {
  text: string;
  output: string;
  project?: string;
  voice_id: string;
  model?: string;
  language_code?: string;
  format?: string;
  seed?: number;
  voice_settings?: VoiceSettings;
  tags?: string[];
  bus?: string;
  no_manifest?: boolean;
  convert_to?: string;
  normalize?: boolean;
  trim_silence?: boolean;
}

interface SfxOptions {
  text: string;
  output: string;
  project?: string;
  duration_seconds?: number;
  prompt_influence?: number;
  format?: string;
  loop?: boolean;
  tags?: string[];
  bus?: string;
  no_manifest?: boolean;
  convert_to?: string;
  normalize?: boolean;
  trim_silence?: boolean;
}

interface InspectOptions {
  file: string;
  project?: string;
}

interface RegenerateOptions {
  file: string;
  project?: string;
  no_manifest?: boolean;
}

// --- Path Resolution ---

function resolveOutputPath(
  output: string,
  projectDir: string
): { fullPath: string; resPath: string } {
  let relative = output;
  if (relative.startsWith("res://")) {
    relative = relative.slice(6);
  }
  const fullPath = resolve(projectDir, relative);
  const resPath = "res://" + relative;
  return { fullPath, resPath };
}

function resolveProjectDir(project?: string): string {
  const dir = project || process.cwd();
  if (!existsSync(resolve(dir, "project.godot"))) {
    throw new Error(
      `Not a Godot project: ${dir} (no project.godot found). Pass "project" in options.`
    );
  }
  return dir;
}

function formatFromOutput(output: string): string {
  const ext = output.split(".").pop()?.toLowerCase();
  switch (ext) {
    case "wav":
      return "pcm_44100";
    case "ogg":
      return "ogg_vorbis";
    default:
      return process.env.AUDIO_GEN_DEFAULT_FORMAT || "mp3_44100_128";
  }
}

function mimeFromFormat(format: string): string {
  if (format.startsWith("pcm")) return "audio/wav";
  if (format.startsWith("ogg")) return "audio/ogg";
  return "audio/mpeg";
}

// --- Post-Processing ---

function postProcessAudio(
  filePath: string,
  opts: AudioPostProcessOptions
): string {
  // Check if ffmpeg is available
  try {
    execSync("which ffmpeg", { encoding: "utf-8", stdio: "pipe" });
  } catch {
    console.error("[audio] ffmpeg not found, skipping post-processing");
    return filePath;
  }

  let currentPath = filePath;

  // Normalize volume
  if (opts.normalize) {
    const tmpPath = filePath.replace(/\.[^.]+$/, "_norm.mp3");
    try {
      execSync(
        `ffmpeg -y -i "${currentPath}" -af loudnorm=I=-16:LRA=11:TP=-1.5 "${tmpPath}"`,
        { encoding: "utf-8", stdio: "pipe", timeout: 30000 }
      );
      unlinkSync(currentPath);
      renameSync(tmpPath, currentPath);
      console.error(`[audio] Normalized: ${currentPath}`);
    } catch (err) {
      console.error(`[audio] Normalization failed: ${err}`);
    }
  }

  // Trim silence
  if (opts.trim_silence) {
    const tmpPath = filePath.replace(/\.[^.]+$/, "_trim.mp3");
    try {
      execSync(
        `ffmpeg -y -i "${currentPath}" -af silenceremove=start_periods=1:start_silence=0.1:start_threshold=-50dB,areverse,silenceremove=start_periods=1:start_silence=0.1:start_threshold=-50dB,areverse "${tmpPath}"`,
        { encoding: "utf-8", stdio: "pipe", timeout: 30000 }
      );
      unlinkSync(currentPath);
      renameSync(tmpPath, currentPath);
      console.error(`[audio] Trimmed silence: ${currentPath}`);
    } catch (err) {
      console.error(`[audio] Silence trimming failed: ${err}`);
    }
  }

  // Format conversion
  if (opts.convert_to) {
    const ext = opts.convert_to.toLowerCase();
    const newPath = currentPath.replace(/\.[^.]+$/, `.${ext}`);
    if (newPath !== currentPath) {
      try {
        const codecFlag = ext === "ogg" ? "-c:a libvorbis -q:a 6" : "";
        execSync(
          `ffmpeg -y -i "${currentPath}" ${codecFlag} "${newPath}"`,
          { encoding: "utf-8", stdio: "pipe", timeout: 30000 }
        );
        unlinkSync(currentPath);
        currentPath = newPath;
        console.error(`[audio] Converted to ${ext}: ${currentPath}`);
      } catch (err) {
        console.error(`[audio] Format conversion failed: ${err}`);
      }
    }
  }

  return currentPath;
}

// --- Commands ---

async function handleVoiceLine(opts: VoiceLineOptions): Promise<void> {
  if (!opts.text) throw new Error("text is required");
  if (!opts.voice_id) throw new Error("voice_id is required");
  if (!opts.output) throw new Error("output is required");

  const projectDir = resolveProjectDir(opts.project);
  let { fullPath, resPath } = resolveOutputPath(opts.output, projectDir);
  const format = opts.format || formatFromOutput(opts.output);
  const resolvedVoiceId = resolveVoicePreset(opts.voice_id);

  mkdirSync(dirname(fullPath), { recursive: true });

  const req: VoiceLineRequest = {
    text: opts.text,
    voice_id: resolvedVoiceId,
    model: opts.model,
    language_code: opts.language_code,
    voice_settings: opts.voice_settings,
    seed: opts.seed,
    output_format: format,
  };

  const result = await generateVoiceLine(req);
  await Bun.write(fullPath, result.audio);
  console.error(`Audio saved: ${fullPath} (${result.audio.length} bytes)`);

  // Post-process if any options are set
  if (opts.normalize || opts.trim_silence || opts.convert_to) {
    const processedPath = postProcessAudio(fullPath, {
      normalize: opts.normalize,
      trim_silence: opts.trim_silence,
      convert_to: opts.convert_to,
    });
    if (processedPath !== fullPath) {
      fullPath = processedPath;
      resPath = resPath.replace(/\.[^.]+$/, fullPath.slice(fullPath.lastIndexOf(".")));
    }
  }

  let manifestPath: string | undefined;
  if (!opts.no_manifest) {
    const input: ManifestInput = {
      type: "voice_line",
      provider: result.provider,
      text: opts.text,
      model: result.model,
      asset_path: resPath,
      format,
      mime_type: result.content_type,
      voice_id: resolvedVoiceId,
      language_code: opts.language_code,
      seed: opts.seed,
      voice_settings: opts.voice_settings as Record<string, unknown>,
      bus: opts.bus,
      tags: opts.tags,
      request_id: result.request_id,
    };
    const manifest = createManifest(input);
    writeManifest(fullPath, manifest);
    manifestPath = manifestResPathFor(resPath);
  }

  const bus = opts.bus || "Voice";
  console.log(
    JSON.stringify(
      {
        success: true,
        type: "voice_line",
        asset_path: resPath,
        manifest_path: manifestPath,
        provider: "elevenlabs",
        model: result.model,
        bytes: result.audio.length,
        suggested_next: [
          {
            command: "import_audio_asset",
            params: { audio_path: resPath },
          },
          {
            command: "attach_audio_stream",
            params: { audio_path: resPath, bus },
          },
        ],
      },
      null,
      2
    )
  );
}

async function handleSfx(opts: SfxOptions): Promise<void> {
  if (!opts.text) throw new Error("text is required");
  if (!opts.output) throw new Error("output is required");

  const projectDir = resolveProjectDir(opts.project);
  let { fullPath, resPath } = resolveOutputPath(opts.output, projectDir);
  const format = opts.format || formatFromOutput(opts.output);

  mkdirSync(dirname(fullPath), { recursive: true });

  const req: SfxRequest = {
    text: opts.text,
    duration_seconds: opts.duration_seconds,
    prompt_influence: opts.prompt_influence,
    output_format: format,
  };

  const result = await generateSfx(req);
  await Bun.write(fullPath, result.audio);
  console.error(`Audio saved: ${fullPath} (${result.audio.length} bytes)`);

  // Post-process if any options are set
  if (opts.normalize || opts.trim_silence || opts.convert_to) {
    const processedPath = postProcessAudio(fullPath, {
      normalize: opts.normalize,
      trim_silence: opts.trim_silence,
      convert_to: opts.convert_to,
    });
    if (processedPath !== fullPath) {
      fullPath = processedPath;
      resPath = resPath.replace(/\.[^.]+$/, fullPath.slice(fullPath.lastIndexOf(".")));
    }
  }

  const audioType = opts.loop ? "ambient_loop" : "sfx";
  let manifestPath: string | undefined;
  if (!opts.no_manifest) {
    const input: ManifestInput = {
      type: audioType,
      provider: result.provider,
      text: opts.text,
      model: result.model,
      asset_path: resPath,
      format,
      mime_type: result.content_type,
      duration_seconds: opts.duration_seconds,
      prompt_influence: opts.prompt_influence,
      loop: opts.loop,
      bus: opts.bus,
      tags: opts.tags,
      request_id: result.request_id,
    };
    const manifest = createManifest(input);
    writeManifest(fullPath, manifest);
    manifestPath = manifestResPathFor(resPath);
  }

  const bus = opts.bus || (opts.loop ? "Ambience" : "SFX");
  console.log(
    JSON.stringify(
      {
        success: true,
        type: audioType,
        asset_path: resPath,
        manifest_path: manifestPath,
        provider: "elevenlabs",
        model: result.model,
        bytes: result.audio.length,
        suggested_next: [
          {
            command: "import_audio_asset",
            params: { audio_path: resPath },
          },
          {
            command: "attach_audio_stream",
            params: { audio_path: resPath, bus },
          },
        ],
      },
      null,
      2
    )
  );
}

async function handleListVoices(): Promise<void> {
  const voices = await listVoices();
  console.log(
    JSON.stringify(
      {
        success: true,
        voices,
        count: voices.length,
      },
      null,
      2
    )
  );
}

async function handleListPresets(): Promise<void> {
  const presets = Object.entries(VOICE_PRESETS).map(([key, v]) => ({
    preset: key,
    voice_id: v.voice_id,
    name: v.name,
    description: v.description,
  }));
  console.log(JSON.stringify({ success: true, presets, count: presets.length }, null, 2));
}

async function handleInspect(opts: InspectOptions): Promise<void> {
  if (!opts.file) throw new Error("file is required");

  const projectDir = resolveProjectDir(opts.project);
  const { fullPath } = resolveOutputPath(opts.file, projectDir);

  if (!existsSync(fullPath)) {
    console.log(
      JSON.stringify({
        success: false,
        error: `File not found: ${fullPath}`,
        code: "FILE_NOT_FOUND",
      })
    );
    process.exit(1);
  }

  const stat = Bun.file(fullPath);
  const manifest = readManifest(fullPath);
  const manifestExists = manifest !== null;

  const info: Record<string, unknown> = {
    success: true,
    file: opts.file,
    size_bytes: stat.size,
    has_manifest: manifestExists,
  };

  if (manifest) {
    info.type = manifest.type;
    info.provider = manifest.provider;
    info.created_at = manifest.created_at;
    info.source_text = manifest.source.text;
    info.model = manifest.source.model;
    info.format = manifest.output.format;
    info.bus = manifest.godot.bus;
    info.tags = manifest.tags;
    if (manifest.source.voice_id) info.voice_id = manifest.source.voice_id;
    if (manifest.regeneration.history.length > 0) {
      info.regeneration_count = manifest.regeneration.history.length;
    }
  }

  console.log(JSON.stringify(info, null, 2));
}

async function handleRegenerate(opts: RegenerateOptions): Promise<void> {
  if (!opts.file) throw new Error("file is required");

  const projectDir = resolveProjectDir(opts.project);
  const { fullPath, resPath } = resolveOutputPath(opts.file, projectDir);

  const existingManifest = readManifest(fullPath);
  if (!existingManifest) {
    console.log(
      JSON.stringify({
        success: false,
        error: `No manifest found for ${opts.file}. Cannot regenerate without source metadata.`,
        code: "NO_MANIFEST",
      })
    );
    process.exit(1);
  }

  const previousManifestPath = manifestPathFor(fullPath);
  const source = existingManifest.source;

  if (existingManifest.type === "voice_line") {
    if (!source.voice_id) {
      throw new Error("Manifest missing voice_id — cannot regenerate voice line");
    }
    const req: VoiceLineRequest = {
      text: source.text,
      voice_id: source.voice_id,
      model: source.model,
      language_code: source.language_code,
      voice_settings: source.voice_settings as VoiceSettings | undefined,
      seed: source.seed,
      output_format: existingManifest.output.format,
    };

    const result = await generateVoiceLine(req);
    await Bun.write(fullPath, result.audio);

    if (!opts.no_manifest) {
      const input: ManifestInput = {
        type: "voice_line",
        provider: result.provider,
        text: source.text,
        model: result.model,
        asset_path: resPath,
        format: existingManifest.output.format,
        mime_type: result.content_type,
        voice_id: source.voice_id,
        language_code: source.language_code,
        seed: source.seed,
        voice_settings: source.voice_settings,
        bus: existingManifest.godot.bus,
        tags: existingManifest.tags,
        request_id: result.request_id,
      };
      const manifest = createRegenerationManifest(
        input,
        previousManifestPath,
        existingManifest
      );
      writeManifest(fullPath, manifest);
    }

    console.log(
      JSON.stringify({
        success: true,
        type: "voice_line",
        asset_path: resPath,
        regenerated: true,
        bytes: result.audio.length,
      })
    );
  } else {
    // SFX or ambient_loop
    const req: SfxRequest = {
      text: source.text,
      duration_seconds: source.duration_seconds,
      prompt_influence: source.prompt_influence,
      output_format: existingManifest.output.format,
    };

    const result = await generateSfx(req);
    await Bun.write(fullPath, result.audio);

    if (!opts.no_manifest) {
      const input: ManifestInput = {
        type: existingManifest.type,
        provider: result.provider,
        text: source.text,
        model: result.model,
        asset_path: resPath,
        format: existingManifest.output.format,
        mime_type: result.content_type,
        duration_seconds: source.duration_seconds,
        prompt_influence: source.prompt_influence,
        loop: source.loop,
        bus: existingManifest.godot.bus,
        tags: existingManifest.tags,
        request_id: result.request_id,
      };
      const manifest = createRegenerationManifest(
        input,
        previousManifestPath,
        existingManifest
      );
      writeManifest(fullPath, manifest);
    }

    console.log(
      JSON.stringify({
        success: true,
        type: existingManifest.type,
        asset_path: resPath,
        regenerated: true,
        bytes: result.audio.length,
      })
    );
  }
}

// --- Main ---

function printUsage(): void {
  const presetList = Object.entries(VOICE_PRESETS)
    .map(([key, v]) => `    ${key.padEnd(12)} - ${v.description}`)
    .join("\n");

  console.error(`Usage: bun generate_audio.ts <command> [options_json]

Commands:
  voice_line    Generate a spoken voice line (TTS)
  sfx           Generate a sound effect
  list_voices   List available ElevenLabs voices
  list_presets  List built-in voice presets
  inspect       Inspect an audio asset and its manifest
  regenerate    Regenerate an audio asset from its manifest

Voice Line Options:
  text          - Text to speak (required)
  voice_id      - ElevenLabs voice ID or preset name (required)
  output        - Output path, e.g. "res://audio/voice/line.mp3" (required)
  project       - Godot project root (default: cwd)
  model         - TTS model (default: eleven_flash_v2_5)
  language_code - Language code, e.g. "en"
  format        - Output format (default: mp3_44100_128)
  seed          - Reproducibility seed
  voice_settings - {stability, similarity_boost, style, use_speaker_boost}
  tags          - Array of tags for categorization
  bus           - Godot audio bus (default: Voice)
  no_manifest   - Skip creating .audio.json manifest
  convert_to    - Convert output format: "ogg", "wav" (requires ffmpeg)
  normalize     - Normalize volume to -3dB peak (requires ffmpeg)
  trim_silence  - Trim leading/trailing silence (requires ffmpeg)

SFX Options:
  text              - Sound description (required)
  output            - Output path (required)
  project           - Godot project root (default: cwd)
  duration_seconds  - Target duration
  prompt_influence  - How closely to follow the prompt (0-1)
  format            - Output format (default: mp3_44100_128)
  loop              - Generate as loopable ambient (default: false)
  tags              - Array of tags
  bus               - Godot audio bus (default: SFX or Ambience if loop)
  no_manifest       - Skip manifest
  convert_to        - Convert output format: "ogg", "wav" (requires ffmpeg)
  normalize         - Normalize volume to -3dB peak (requires ffmpeg)
  trim_silence      - Trim leading/trailing silence (requires ffmpeg)

Voice Presets (use as voice_id):
${presetList}

Environment Variables:
  ELEVENLABS_API_KEY           - ElevenLabs API key (required)
  AUDIO_GEN_DEFAULT_FORMAT     - Default format (mp3_44100_128)
  AUDIO_GEN_DEFAULT_VOICE_MODEL - Default TTS model (eleven_flash_v2_5)
  AUDIO_GEN_DEFAULT_SFX_MODEL  - Default SFX model (eleven_text_to_sound_v2)
`);
}

async function main(): Promise<void> {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    printUsage();
    process.exit(1);
  }

  const command = args[0];
  let options: Record<string, unknown> = {};

  if (args[1]) {
    try {
      options = JSON.parse(args[1]);
    } catch {
      console.error(
        JSON.stringify({
          success: false,
          error: `Invalid JSON options: ${args[1]}`,
          code: "INVALID_JSON",
        })
      );
      process.exit(1);
    }
  }

  try {
    switch (command) {
      case "voice_line":
        await handleVoiceLine(options as unknown as VoiceLineOptions);
        break;
      case "sfx":
        await handleSfx(options as unknown as SfxOptions);
        break;
      case "list_voices":
        await handleListVoices();
        break;
      case "list_presets":
        await handleListPresets();
        break;
      case "inspect":
        await handleInspect(options as unknown as InspectOptions);
        break;
      case "regenerate":
        await handleRegenerate(options as unknown as RegenerateOptions);
        break;
      default:
        console.error(
          JSON.stringify({
            success: false,
            error: `Unknown command: ${command}`,
            code: "INVALID_AUDIO_TYPE",
            available: [
              "voice_line",
              "sfx",
              "list_voices",
              "list_presets",
              "inspect",
              "regenerate",
            ],
          })
        );
        process.exit(1);
    }
  } catch (err) {
    if (err instanceof ProviderError) {
      console.error(
        JSON.stringify({
          success: false,
          error: err.message,
          code: err.code,
        })
      );
    } else {
      console.error(
        JSON.stringify({
          success: false,
          error: String(err),
          code: "UNKNOWN_ERROR",
        })
      );
    }
    process.exit(1);
  }
}

main();
