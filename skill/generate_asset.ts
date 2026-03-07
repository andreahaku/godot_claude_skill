#!/usr/bin/env bun
/**
 * AI asset generator for Godot projects.
 * Generates images using Google Gemini/Imagen or OpenAI DALL-E
 * and saves them to the Godot project's asset directory.
 *
 * Uses structured JSON prompt building internally for dramatically
 * improved image generation quality — each aspect (subject, style,
 * composition) is isolated during construction to prevent concept bleeding.
 *
 * Usage: bun generate_asset.ts <prompt> [options_json]
 *
 * Environment variables:
 *   GOOGLE_AI_API_KEY   - Google AI API key (for Gemini/Imagen)
 *   OPENAI_API_KEY      - OpenAI API key (for DALL-E)
 *   ASSET_GEN_PROVIDER  - "gemini" (default if Google key set) or "openai"
 *   GEMINI_IMAGE_MODEL  - Model name (default: imagen-4.0-generate-001)
 */

import { mkdirSync, existsSync, writeFileSync } from "fs";
import { dirname, resolve, basename } from "path";

const GOOGLE_API_KEY =
  process.env.GOOGLE_AI_API_KEY || process.env.GEMINI_API_KEY || "";
const OPENAI_API_KEY = process.env.OPENAI_API_KEY || "";
const PROVIDER =
  process.env.ASSET_GEN_PROVIDER ||
  (GOOGLE_API_KEY ? "gemini" : OPENAI_API_KEY ? "openai" : "");
const GEMINI_MODEL =
  process.env.GEMINI_IMAGE_MODEL || "imagen-4.0-generate-001";

// --- Structured Prompt Types ---

interface StructuredPrompt {
  subject: {
    type: string;
    description: string;
    position: string;
    details: string;
  };
  composition: {
    framing: string;
    angle: string;
    focus_point: string;
  };
  style: {
    medium: string;
    aesthetic: string;
    color_palette_notes: string;
    rendering_notes: string;
  };
  technical: {
    background: string;
    output_type: string;
    constraints: string[];
  };
  negative_prompt: string[];
}

interface GameArtPreset {
  subject_defaults: Record<string, string>;
  composition: {
    framing: string;
    angle: string;
    focus_point: string;
  };
  style: {
    medium: string;
    aesthetic: string;
    rendering_notes: string;
  };
  technical: {
    background: string;
    output_type: string;
    constraints: string[];
  };
  negative_prompt: string[];
}

interface AssetManifest {
  prompt: string;
  style: string;
  provider: string;
  model: string;
  timestamp: string;
  output_path: string;
  structured_prompt: StructuredPrompt;
  options: {
    size?: string;
    aspect_ratio?: string;
    remove_bg?: boolean;
    resize?: string;
    trim?: boolean;
    quality?: string;
    color_palette?: string[];
    style_notes?: string;
  };
  post_processing: {
    bg_removed: boolean;
    trimmed: boolean;
    resized_to: string | null;
  };
}

interface GenerateOptions {
  output: string;
  project?: string;
  size?: string;
  style?: string;
  count?: number;
  negative?: string;
  aspect_ratio?: string;
  remove_bg?: boolean;
  bg_threshold?: number;
  resize?: string;
  trim?: boolean;
  json_prompt?: boolean;
  style_reference?: string;
  style_notes?: string;
  color_palette?: string[];
  no_manifest?: boolean;
  quality?: string;
}

// --- Universal Negative Prompt ---

const UNIVERSAL_NEGATIVES: string[] = [
  "text",
  "labels",
  "words",
  "letters",
  "numbers",
  "watermarks",
  "signatures",
  "annotations",
  "captions",
  "low quality",
  "blurry",
  "extra limbs",
];

// --- Game Art Presets (structured JSON schemas) ---

const GAME_ART_PRESETS: Record<string, GameArtPreset> = {
  pixel_art: {
    subject_defaults: {
      details: "clean single image, clear edges",
    },
    composition: {
      framing: "full_view",
      angle: "front_facing",
      focus_point: "whole_subject",
    },
    style: {
      medium: "pixel_art",
      aesthetic: "retro 16-bit game art",
      rendering_notes: "crisp sharp pixels, no anti-aliasing, no smoothing, solid flat colors, limited color palette",
    },
    technical: {
      background: "transparent PNG",
      output_type: "game_asset_sprite",
      constraints: ["no gradients", "no sub-pixel rendering", "clean pixel boundaries"],
    },
    negative_prompt: ["anti-aliasing", "smooth gradients", "photorealistic", "3D render"],
  },

  pixel_art_character: {
    subject_defaults: {
      position: "centered in frame",
      details: "single character, black outline, game-ready asset",
    },
    composition: {
      framing: "full_body",
      angle: "front_facing",
      focus_point: "character_center",
    },
    style: {
      medium: "pixel_art",
      aesthetic: "retro 16-bit character sprite",
      rendering_notes: "crisp sharp pixels, no anti-aliasing, no smoothing, solid flat colors, black outline around character",
    },
    technical: {
      background: "transparent PNG",
      output_type: "character_sprite",
      constraints: ["single character only", "no background elements", "clear silhouette"],
    },
    negative_prompt: ["anti-aliasing", "multiple characters", "background scenery", "3D render"],
  },

  pixel_art_tileset: {
    subject_defaults: {
      details: "tiles arranged in a strict uniform grid, each tile same size, seamless tile edges",
    },
    composition: {
      framing: "grid_layout",
      angle: "top_down",
      focus_point: "tile_grid",
    },
    style: {
      medium: "pixel_art",
      aesthetic: "retro game tileset art",
      rendering_notes: "crisp sharp pixels, no anti-aliasing, consistent art style across all tiles, seamless edges",
    },
    technical: {
      background: "transparent PNG",
      output_type: "tileset_grid",
      constraints: ["uniform tile dimensions", "seamless edges", "consistent style across tiles"],
    },
    negative_prompt: ["anti-aliasing", "varying tile sizes", "perspective distortion", "3D render"],
  },

  hand_drawn: {
    subject_defaults: {
      details: "clean defined lines, vibrant colors",
    },
    composition: {
      framing: "full_view",
      angle: "front_facing",
      focus_point: "whole_subject",
    },
    style: {
      medium: "hand_drawn_illustration",
      aesthetic: "vibrant hand-drawn game art illustration",
      rendering_notes: "clean defined lines, vibrant saturated colors, illustration style, slight hand-crafted feel",
    },
    technical: {
      background: "transparent PNG",
      output_type: "game_asset_illustration",
      constraints: ["clean lines", "no rough sketchy edges unless intentional"],
    },
    negative_prompt: ["photorealistic", "3D render", "pixel art", "blurry lines"],
  },

  realistic: {
    subject_defaults: {
      details: "detailed texture, physically-based rendering ready",
    },
    composition: {
      framing: "full_view",
      angle: "three_quarter",
      focus_point: "whole_subject",
    },
    style: {
      medium: "realistic_digital",
      aesthetic: "photorealistic PBR-ready game asset",
      rendering_notes: "detailed texture, physically-based rendering ready, high-frequency detail, seamless edges where applicable",
    },
    technical: {
      background: "neutral or seamless",
      output_type: "pbr_texture_or_asset",
      constraints: ["seamless edges", "consistent lighting", "no baked shadows unless appropriate"],
    },
    negative_prompt: ["cartoon", "stylized", "low resolution", "pixel art"],
  },

  ui: {
    subject_defaults: {
      details: "clean UI element, minimal design",
    },
    composition: {
      framing: "centered",
      angle: "flat_front",
      focus_point: "element_center",
    },
    style: {
      medium: "flat_vector",
      aesthetic: "clean modern flat UI design",
      rendering_notes: "flat design, sharp vector-like edges, minimal, clean geometric shapes",
    },
    technical: {
      background: "transparent PNG",
      output_type: "ui_element",
      constraints: ["sharp edges", "no texture noise", "consistent stroke width"],
    },
    negative_prompt: ["photorealistic", "3D", "textured", "hand-drawn", "sketchy"],
  },

  tileset: {
    subject_defaults: {
      details: "tiles in strict uniform grid, each tile same dimensions",
    },
    composition: {
      framing: "grid_layout",
      angle: "top_down",
      focus_point: "tile_grid",
    },
    style: {
      medium: "digital_painting",
      aesthetic: "game tileset, consistent style",
      rendering_notes: "seamless tileable pattern, consistent art style, uniform lighting across tiles",
    },
    technical: {
      background: "transparent PNG",
      output_type: "tileset_grid",
      constraints: ["seamless tileable", "uniform dimensions", "consistent perspective"],
    },
    negative_prompt: ["perspective distortion", "varying styles", "inconsistent lighting"],
  },

  icon: {
    subject_defaults: {
      position: "centered in frame",
      details: "bold silhouette, simple instantly recognizable design, single object",
    },
    composition: {
      framing: "centered_tight",
      angle: "front_facing",
      focus_point: "icon_center",
    },
    style: {
      medium: "icon_design",
      aesthetic: "bold clean game icon",
      rendering_notes: "clear bold silhouette, simple instantly recognizable design, strong contrast",
    },
    technical: {
      background: "transparent PNG",
      output_type: "game_icon",
      constraints: ["single object", "readable at small sizes", "strong silhouette"],
    },
    negative_prompt: ["complex details", "multiple objects", "background scenery", "text"],
  },

  character: {
    subject_defaults: {
      position: "centered in frame",
      details: "single character, clear outline, game-ready, clean edges",
    },
    composition: {
      framing: "full_body",
      angle: "front_facing",
      focus_point: "character_center",
    },
    style: {
      medium: "digital_character_art",
      aesthetic: "game character sprite art",
      rendering_notes: "clear outline, game-ready, clean defined edges, appealing character design",
    },
    technical: {
      background: "transparent PNG",
      output_type: "character_sprite",
      constraints: ["single character", "no background", "clear silhouette"],
    },
    negative_prompt: ["multiple characters", "busy background", "cropped limbs"],
  },

  environment: {
    subject_defaults: {
      details: "atmospheric, detailed scene",
    },
    composition: {
      framing: "wide_shot",
      angle: "eye_level_or_slightly_elevated",
      focus_point: "scene_center",
    },
    style: {
      medium: "digital_painting",
      aesthetic: "atmospheric game environment art",
      rendering_notes: "atmospheric, detailed, depth and mood, environmental storytelling",
    },
    technical: {
      background: "included as part of scene",
      output_type: "environment_background",
      constraints: ["wide composition", "consistent perspective", "layered depth"],
    },
    negative_prompt: ["characters in foreground", "UI elements", "cropped edges"],
  },

  spritesheet: {
    subject_defaults: {
      details: "multiple frames in a single horizontal row from left to right, each frame exactly the same size, evenly spaced, consistent style across all frames",
    },
    composition: {
      framing: "horizontal_strip",
      angle: "front_facing",
      focus_point: "all_frames_equally",
    },
    style: {
      medium: "sprite_animation",
      aesthetic: "game-ready animation spritesheet",
      rendering_notes: "consistent style across all frames, smooth animation progression, evenly spaced frames",
    },
    technical: {
      background: "transparent PNG",
      output_type: "spritesheet_animation",
      constraints: ["uniform frame size", "even spacing", "horizontal row layout", "consistent character proportions"],
    },
    negative_prompt: ["varying frame sizes", "inconsistent style between frames", "overlapping frames"],
  },
};

// Legacy flat style presets for backward compatibility in help text
const STYLE_PRESET_NAMES = Object.keys(GAME_ART_PRESETS);

// --- Structured Prompt Builder ---

/**
 * Infers a subject type from the user's prompt text.
 */
function inferSubjectType(prompt: string): string {
  const lower = prompt.toLowerCase();
  if (/\b(character|hero|villain|knight|warrior|mage|npc|player)\b/.test(lower)) return "character";
  if (/\b(tile|tileset|terrain|ground|floor|wall)\b/.test(lower)) return "tileset";
  if (/\b(icon|button|badge|emblem|symbol)\b/.test(lower)) return "icon";
  if (/\b(ui|interface|menu|hud|panel|dialog)\b/.test(lower)) return "ui_element";
  if (/\b(environment|landscape|scene|background|world|forest|dungeon|cave)\b/.test(lower)) return "environment";
  if (/\b(sprite\s*sheet|animation|walk\s*cycle|run\s*cycle|frames)\b/.test(lower)) return "spritesheet";
  if (/\b(item|weapon|sword|shield|potion|armor|tool)\b/.test(lower)) return "item";
  if (/\b(effect|particle|explosion|fire|smoke|magic)\b/.test(lower)) return "effect";
  return "asset";
}

/**
 * Builds a structured JSON prompt object by merging user intent with preset defaults and options.
 */
function buildStructuredPromptObject(
  userPrompt: string,
  preset: GameArtPreset | null,
  options: GenerateOptions
): StructuredPrompt {
  const subjectType = inferSubjectType(userPrompt);

  // Base structure from user prompt
  const structured: StructuredPrompt = {
    subject: {
      type: subjectType,
      description: userPrompt,
      position: "center",
      details: "single clean image",
    },
    composition: {
      framing: "full_view",
      angle: "front_facing",
      focus_point: "whole_subject",
    },
    style: {
      medium: "digital_art",
      aesthetic: "game art",
      color_palette_notes: "appealing color palette",
      rendering_notes: "",
    },
    technical: {
      background: "transparent PNG",
      output_type: "game_asset",
      constraints: [],
    },
    negative_prompt: [...UNIVERSAL_NEGATIVES],
  };

  // Overlay preset defaults
  if (preset) {
    // Subject defaults
    if (preset.subject_defaults.position) {
      structured.subject.position = preset.subject_defaults.position;
    }
    if (preset.subject_defaults.details) {
      structured.subject.details = preset.subject_defaults.details;
    }

    // Composition
    structured.composition = { ...preset.composition };

    // Style
    structured.style.medium = preset.style.medium;
    structured.style.aesthetic = preset.style.aesthetic;
    structured.style.rendering_notes = preset.style.rendering_notes;

    // Technical
    structured.technical.background = preset.technical.background;
    structured.technical.output_type = preset.technical.output_type;
    structured.technical.constraints = [...preset.technical.constraints];

    // Merge negative prompts (preset negatives + universal)
    structured.negative_prompt = [...UNIVERSAL_NEGATIVES, ...preset.negative_prompt];
  }

  // Apply color_palette option
  if (options.color_palette && options.color_palette.length > 0) {
    structured.style.color_palette_notes =
      `use primarily these colors: ${options.color_palette.join(", ")}`;
  }

  // Apply style_notes option
  if (options.style_notes) {
    structured.style.rendering_notes = structured.style.rendering_notes
      ? `${structured.style.rendering_notes}, ${options.style_notes}`
      : options.style_notes;
  }

  // Apply quality tier
  if (options.quality === "draft") {
    // No extra quality modifiers for draft — keep it simple for speed
  } else if (options.quality === "final") {
    structured.style.aesthetic = `${structured.style.aesthetic}, highest quality, production-ready, premium game art`;
    structured.technical.constraints.push("maximum detail", "publication-ready quality");
  }
  // "standard" (default) — no modifications needed

  // Apply user negative prompt
  if (options.negative) {
    const userNegatives = options.negative.split(",").map((s) => s.trim()).filter(Boolean);
    structured.negative_prompt.push(...userNegatives);
  }

  // Deduplicate negative prompts
  structured.negative_prompt = [...new Set(structured.negative_prompt)];

  return structured;
}

/**
 * Renders a StructuredPrompt into a text prompt string suitable for image generation APIs.
 * The structured format prevents concept bleeding by keeping each aspect isolated.
 */
function renderStructuredPrompt(
  structured: StructuredPrompt,
  options: GenerateOptions
): string {
  const lines: string[] = [];

  // Subject line
  const subjectParts = [structured.subject.description];
  if (structured.subject.details) {
    subjectParts.push(structured.subject.details);
  }
  if (structured.subject.position !== "center") {
    subjectParts.push(`${structured.subject.position} in frame`);
  } else {
    subjectParts.push("centered in frame");
  }
  lines.push(`Subject: ${subjectParts.join(", ")}`);

  // Composition line
  const framingReadable = structured.composition.framing.replace(/_/g, " ");
  const angleReadable = structured.composition.angle.replace(/_/g, " ");
  lines.push(`Composition: ${framingReadable} view, ${angleReadable} angle`);

  // Style line
  const styleParts = [structured.style.medium.replace(/_/g, " ")];
  styleParts.push(structured.style.aesthetic);
  if (structured.style.rendering_notes) {
    styleParts.push(structured.style.rendering_notes);
  }
  lines.push(`Style: ${styleParts.join(", ")}`);

  // Color palette line (only if specific)
  if (structured.style.color_palette_notes && structured.style.color_palette_notes !== "appealing color palette") {
    lines.push(`Color palette: ${structured.style.color_palette_notes}`);
  }

  // Background line
  lines.push(`Background: ${structured.technical.background}`);

  // Technical line
  const techParts = [structured.technical.output_type.replace(/_/g, " ")];
  if (structured.technical.constraints.length > 0) {
    techParts.push(...structured.technical.constraints);
  }
  lines.push(`Technical: ${techParts.join(", ")}`);

  // Style reference
  if (options.style_reference) {
    lines.push(
      `Style reference: match the art style, color palette, and level of detail from the reference image at ${options.style_reference}. Maintain consistency.`
    );
  }

  // Negative prompt line
  if (structured.negative_prompt.length > 0) {
    lines.push(`Do NOT include: ${structured.negative_prompt.join(", ")}`);
  }

  return lines.join("\n");
}

/**
 * Main entry point for building the prompt. Builds JSON structure internally,
 * then renders to provider-appropriate text.
 */
function buildStructuredPrompt(
  userPrompt: string,
  preset: GameArtPreset | null,
  options: GenerateOptions
): { promptText: string; structuredData: StructuredPrompt } {
  const structured = buildStructuredPromptObject(userPrompt, preset, options);
  const promptText = renderStructuredPrompt(structured, options);
  return { promptText, structuredData: structured };
}

// --- Google Gemini / Imagen Provider ---

async function generateWithGemini(
  prompt: string,
  options: GenerateOptions
): Promise<Buffer[]> {
  if (!GOOGLE_API_KEY) {
    throw new Error(
      "GOOGLE_AI_API_KEY or GEMINI_API_KEY environment variable required"
    );
  }

  const count = Math.min(options.count || 1, 4);
  const aspectRatio = options.aspect_ratio || "1:1";

  // Use Imagen API
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:predict?key=${GOOGLE_API_KEY}`;
  console.error(`Generating with ${GEMINI_MODEL}...`);

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    signal: AbortSignal.timeout(120_000),
    body: JSON.stringify({
      instances: [{ prompt }],
      parameters: {
        sampleCount: count,
        aspectRatio,
        outputOptions: { mimeType: "image/png" },
      },
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    // If Imagen fails, try Gemini generateContent as fallback
    if (response.status === 404 || response.status === 400) {
      return generateWithGeminiContent(prompt, options);
    }
    throw new Error(`Imagen API error (${response.status}): ${errorText}`);
  }

  const data = await response.json();
  const images: Buffer[] = [];

  for (const prediction of data.predictions || []) {
    if (prediction.bytesBase64Encoded) {
      images.push(Buffer.from(prediction.bytesBase64Encoded, "base64"));
    }
  }

  if (images.length === 0) {
    // Fallback to Gemini generateContent
    return generateWithGeminiContent(prompt, options);
  }

  return images;
}

async function generateWithGeminiContent(
  prompt: string,
  options: GenerateOptions
): Promise<Buffer[]> {
  if (!GOOGLE_API_KEY) {
    throw new Error("GOOGLE_AI_API_KEY required");
  }

  const model =
    process.env.GEMINI_CONTENT_MODEL || "gemini-2.5-flash-image";
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GOOGLE_API_KEY}`;
  console.error(`Generating with ${model} (fallback)...`);

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    signal: AbortSignal.timeout(120_000),
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        responseModalities: ["IMAGE", "TEXT"],
      },
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(
      `Gemini generateContent error (${response.status}): ${errorText}`
    );
  }

  const data = await response.json();
  const images: Buffer[] = [];

  for (const candidate of data.candidates || []) {
    for (const part of candidate.content?.parts || []) {
      if (part.inlineData?.data) {
        images.push(Buffer.from(part.inlineData.data, "base64"));
      }
    }
  }

  if (images.length === 0) {
    throw new Error(
      "No images in response. Response: " +
        JSON.stringify(data).slice(0, 500)
    );
  }

  return images;
}

// --- OpenAI DALL-E Provider ---

async function generateWithOpenAI(
  prompt: string,
  options: GenerateOptions
): Promise<Buffer[]> {
  if (!OPENAI_API_KEY) {
    throw new Error("OPENAI_API_KEY environment variable required");
  }

  const size = options.size || "1024x1024";
  const validSizes = ["1024x1024", "1024x1792", "1792x1024"];
  const dalleSize = validSizes.includes(size) ? size : "1024x1024";

  console.error(`Generating with DALL-E 3...`);
  const response = await fetch("https://api.openai.com/v1/images/generations", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_API_KEY}`,
    },
    signal: AbortSignal.timeout(120_000),
    body: JSON.stringify({
      model: "dall-e-3",
      prompt,
      n: 1, // DALL-E 3 only supports n=1
      size: dalleSize,
      response_format: "b64_json",
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`OpenAI API error (${response.status}): ${errorText}`);
  }

  const data = (await response.json()) as {
    data: Array<{ b64_json: string }>;
  };
  return data.data.map((item) => Buffer.from(item.b64_json, "base64"));
}

// --- Post-processing ---

/**
 * Post-processes a generated PNG: removes white background via flood-fill,
 * trims transparent padding, and resizes to target dimensions.
 * All done in a single Python/PIL call for efficiency.
 */
function postProcessImage(
  pngBuffer: Buffer,
  opts: { removeBg: boolean; threshold: number; trim: boolean; resize?: string }
): Buffer {
  const { execSync } = require("child_process");
  const { writeFileSync: fsWriteFileSync, readFileSync, unlinkSync } = require("fs");

  const uid = crypto.randomUUID().slice(0, 8);
  const tmpIn = `/tmp/_asset_gen_${uid}_in.png`;
  const tmpOut = `/tmp/_asset_gen_${uid}_out.png`;

  fsWriteFileSync(tmpIn, pngBuffer);

  // Parse resize target
  let resizeW = 0;
  let resizeH = 0;
  if (opts.resize) {
    const parts = opts.resize.split("x");
    resizeW = parseInt(parts[0]) || 0;
    resizeH = parseInt(parts[1] || parts[0]) || resizeW;
  }

  // Single Python script handles everything (pure PIL, no numpy dependency)
  const script = `
import sys
from PIL import Image

img = Image.open('${tmpIn}').convert('RGBA')

if ${opts.removeBg ? "True" : "False"}:
    threshold = ${opts.threshold}
    w, h = img.size
    pixels = img.load()
    visited = [[False]*w for _ in range(h)]
    stack = []
    # Seed all edge pixels that are white/near-white
    for x in range(w):
        for y in [0, h-1]:
            r, g, b, a = pixels[x, y]
            if r >= threshold and g >= threshold and b >= threshold:
                stack.append((x, y))
                visited[y][x] = True
    for y in range(h):
        for x in [0, w-1]:
            r, g, b, a = pixels[x, y]
            if r >= threshold and g >= threshold and b >= threshold:
                if not visited[y][x]:
                    stack.append((x, y))
                    visited[y][x] = True
    # DFS flood fill
    sys.setrecursionlimit(10000)
    while stack:
        cx, cy = stack.pop()
        r, g, b, a = pixels[cx, cy]
        pixels[cx, cy] = (r, g, b, 0)
        for dx, dy in [(-1,0),(1,0),(0,-1),(0,1)]:
            nx, ny = cx+dx, cy+dy
            if 0 <= nx < w and 0 <= ny < h and not visited[ny][nx]:
                r2, g2, b2, a2 = pixels[nx, ny]
                if r2 >= threshold and g2 >= threshold and b2 >= threshold:
                    visited[ny][nx] = True
                    stack.append((nx, ny))

if ${opts.trim ? "True" : "False"}:
    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)

resize_w = ${resizeW}
resize_h = ${resizeH}
if resize_w > 0 and resize_h > 0:
    img = img.resize((resize_w, resize_h), Image.NEAREST)

img.save('${tmpOut}', 'PNG')
`;

  const tmpScript = `/tmp/_asset_gen_${uid}_script.py`;
  fsWriteFileSync(tmpScript, script);

  try {
    execSync(`python3 "${tmpScript}"`, {
      encoding: "utf-8",
      timeout: 30000,
    });
    const result = Buffer.from(readFileSync(tmpOut));
    return result;
  } catch (err) {
    // If post-processing fails, return original
    console.error(`Warning: post-processing failed: ${err}`);
    return pngBuffer;
  } finally {
    try { unlinkSync(tmpIn); } catch {}
    try { unlinkSync(tmpOut); } catch {}
    try { unlinkSync(tmpScript); } catch {}
  }
}

// --- Asset Manifest ---

/**
 * Writes a sidecar .asset.json manifest file next to the generated image.
 */
function writeAssetManifest(
  imagePath: string,
  resPath: string,
  manifest: AssetManifest
): void {
  const manifestPath = imagePath.replace(/\.[^.]+$/, ".asset.json");
  writeFileSync(manifestPath, JSON.stringify(manifest, null, 2), "utf-8");
  console.error(`Manifest written: ${manifestPath}`);
}

// --- Main ---

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

/**
 * Determines the model name used for manifest logging.
 */
function getModelName(): string {
  if (PROVIDER === "openai") return "dall-e-3";
  return GEMINI_MODEL;
}

async function main() {
  const args = process.argv.slice(2);

  if (args.length === 0) {
    console.error(
      "Usage: bun generate_asset.ts <prompt> [options_json]\n"
    );
    console.error("Options JSON:");
    console.error(
      '  output  - Output path, e.g. "res://assets/sprite.png" (required)'
    );
    console.error(
      '  project - Godot project root (default: current directory)'
    );
    console.error('  size    - Image dimensions, e.g. "1024x1024"');
    console.error(
      '  style   - Style preset: ' + STYLE_PRESET_NAMES.join(", ")
    );
    console.error("  count   - Number of variants (1-4, default: 1)");
    console.error('  negative - Negative prompt, e.g. "blurry, text"');
    console.error(
      '  aspect_ratio - Aspect ratio for Imagen, e.g. "1:1", "16:9"'
    );
    console.error(
      '  resize   - Resize output, e.g. "32x32", "64x64", "128" (square)'
    );
    console.error(
      "  remove_bg - Remove white background -> transparency (default: true)"
    );
    console.error(
      "  trim     - Trim transparent padding after bg removal (default: true)"
    );
    console.error(
      "  bg_threshold - White detection threshold 0-255 (default: 240)"
    );
    console.error(
      '  quality  - Generation quality: "draft", "standard" (default), "final"'
    );
    console.error(
      '  style_notes  - Additional style notes, e.g. "desaturated forest tones"'
    );
    console.error(
      '  style_reference - Path to reference image for style consistency'
    );
    console.error(
      '  color_palette - Array of hex colors, e.g. ["#2d5a27", "#8b4513"]'
    );
    console.error(
      "  no_manifest - Skip creating .asset.json manifest (default: false)\n"
    );
    console.error("Environment variables:");
    console.error("  GOOGLE_AI_API_KEY   - Google AI key (Gemini/Imagen)");
    console.error("  OPENAI_API_KEY      - OpenAI key (DALL-E 3)");
    console.error(
      '  ASSET_GEN_PROVIDER  - "gemini" (default) or "openai"'
    );
    console.error(
      "  GEMINI_IMAGE_MODEL  - Imagen model (default: imagen-4.0-generate-001)"
    );
    process.exit(1);
  }

  if (!PROVIDER) {
    console.error(
      JSON.stringify({
        success: false,
        error:
          "No API key configured. Set GOOGLE_AI_API_KEY or OPENAI_API_KEY environment variable.",
      })
    );
    process.exit(1);
  }

  const basePrompt = args[0];
  let options: GenerateOptions = {
    output: "res://assets/generated/image.png",
  };

  if (args[1]) {
    try {
      options = { ...options, ...JSON.parse(args[1]) };
    } catch {
      console.error("Invalid JSON options:", args[1]);
      process.exit(1);
    }
  }

  // Resolve project directory
  const projectDir = options.project || process.cwd();
  if (!existsSync(resolve(projectDir, "project.godot"))) {
    console.error(
      JSON.stringify({
        success: false,
        error: `Not a Godot project: ${projectDir} (no project.godot found). Pass "project" in options.`,
      })
    );
    process.exit(1);
  }

  // Look up preset
  const preset = (options.style && GAME_ART_PRESETS[options.style]) || null;
  if (options.style && !preset) {
    console.error(`Warning: unknown style preset "${options.style}", using defaults. Available: ${STYLE_PRESET_NAMES.join(", ")}`);
  }

  // Build structured prompt
  const { promptText, structuredData } = buildStructuredPrompt(basePrompt, preset, options);

  console.error(`Structured prompt built (${promptText.length} chars)`);

  // Resolve output path
  const { fullPath, resPath } = resolveOutputPath(options.output, projectDir);
  mkdirSync(dirname(fullPath), { recursive: true });

  try {
    let images: Buffer[];
    if (PROVIDER === "openai") {
      images = await generateWithOpenAI(promptText, options);
    } else {
      images = await generateWithGemini(promptText, options);
    }

    // Post-process: background removal, trim, resize
    const shouldRemoveBg = options.remove_bg !== false;
    const shouldTrim = options.trim !== false;
    const bgThreshold = options.bg_threshold ?? 240;
    if (shouldRemoveBg || options.resize) {
      console.error(`Post-processing ${images.length} image(s)...`);
      for (let i = 0; i < images.length; i++) {
        images[i] = postProcessImage(images[i], {
          removeBg: shouldRemoveBg,
          threshold: bgThreshold,
          trim: shouldTrim,
          resize: options.resize,
        });
      }
    }

    // Save images
    const savedPaths: string[] = [];
    const savedFullPaths: string[] = [];
    if (images.length === 1) {
      await Bun.write(fullPath, images[0]);
      savedPaths.push(resPath);
      savedFullPaths.push(fullPath);
    } else {
      const ext = fullPath.substring(fullPath.lastIndexOf("."));
      const base = fullPath.substring(0, fullPath.lastIndexOf("."));
      const resBase = resPath.substring(0, resPath.lastIndexOf("."));
      const resExt = resPath.substring(resPath.lastIndexOf("."));
      for (let i = 0; i < images.length; i++) {
        const path = `${base}_${i}${ext}`;
        await Bun.write(path, images[i]);
        savedPaths.push(`${resBase}_${i}${resExt}`);
        savedFullPaths.push(path);
      }
    }

    // Write asset manifests
    if (!options.no_manifest) {
      const timestamp = new Date().toISOString();
      const modelName = getModelName();
      for (let i = 0; i < savedFullPaths.length; i++) {
        const manifest: AssetManifest = {
          prompt: basePrompt,
          style: options.style || "none",
          provider: PROVIDER,
          model: modelName,
          timestamp,
          output_path: savedPaths[i],
          structured_prompt: structuredData,
          options: {
            size: options.size,
            aspect_ratio: options.aspect_ratio,
            remove_bg: options.remove_bg,
            resize: options.resize,
            trim: options.trim,
            quality: options.quality,
            color_palette: options.color_palette,
            style_notes: options.style_notes,
          },
          post_processing: {
            bg_removed: shouldRemoveBg,
            trimmed: shouldTrim,
            resized_to: options.resize || null,
          },
        };
        writeAssetManifest(savedFullPaths[i], savedPaths[i], manifest);
      }
    }

    console.log(
      JSON.stringify(
        {
          success: true,
          paths: savedPaths,
          prompt: basePrompt,
          style: options.style || "none",
          provider: PROVIDER,
          count: images.length,
        },
        null,
        2
      )
    );
  } catch (err) {
    console.error(
      JSON.stringify({
        success: false,
        error: String(err),
        provider: PROVIDER,
      })
    );
    process.exit(1);
  }
}

main();
