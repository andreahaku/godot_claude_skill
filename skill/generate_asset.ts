#!/usr/bin/env bun
/**
 * AI asset generator for Godot projects.
 * Generates images using Google Gemini/Imagen or OpenAI DALL-E
 * and saves them to the Godot project's asset directory.
 *
 * Usage: bun generate_asset.ts <prompt> [options_json]
 *
 * Environment variables:
 *   GOOGLE_AI_API_KEY   - Google AI API key (for Gemini/Imagen)
 *   OPENAI_API_KEY      - OpenAI API key (for DALL-E)
 *   ASSET_GEN_PROVIDER  - "gemini" (default if Google key set) or "openai"
 *   GEMINI_IMAGE_MODEL  - Model name (default: imagen-3.0-generate-001)
 */

import { mkdirSync, existsSync } from "fs";
import { dirname, resolve } from "path";

const GOOGLE_API_KEY =
  process.env.GOOGLE_AI_API_KEY || process.env.GEMINI_API_KEY || "";
const OPENAI_API_KEY = process.env.OPENAI_API_KEY || "";
const PROVIDER =
  process.env.ASSET_GEN_PROVIDER ||
  (GOOGLE_API_KEY ? "gemini" : OPENAI_API_KEY ? "openai" : "");
const GEMINI_MODEL =
  process.env.GEMINI_IMAGE_MODEL || "imagen-3.0-generate-001";

// Style presets that enhance prompts for game asset generation
const STYLE_PRESETS: Record<string, string> = {
  pixel_art:
    "pixel art style, crisp pixels, no anti-aliasing, retro game art, transparent background",
  pixel_art_character:
    "pixel art character sprite, side view, crisp pixels, no anti-aliasing, transparent background, game-ready",
  pixel_art_tileset:
    "pixel art tileset, top-down view, crisp pixels, seamless tiles, retro game art, consistent style",
  hand_drawn:
    "hand-drawn illustration style, game art, clean lines, vibrant colors",
  realistic:
    "realistic detailed texture, physically-based rendering ready, game asset",
  ui: "clean UI element, flat design, sharp edges, transparent background, game interface",
  tileset:
    "seamless tileable pattern, game tileset, consistent style, top-down perspective",
  icon: "game icon, clear silhouette, simple recognizable design, transparent background",
  character:
    "character sprite, clear outline, game-ready, transparent background",
  environment: "environment art, game background, atmospheric, detailed",
  spritesheet:
    "spritesheet with multiple frames arranged in a grid, consistent size per frame, transparent background, game-ready",
};

interface GenerateOptions {
  output: string; // Output path (res:// or relative)
  project?: string; // Godot project root (defaults to cwd)
  size?: string; // Image size (e.g., "1024x1024")
  style?: string; // Style preset name
  count?: number; // Number of variants
  negative?: string; // Negative prompt
  aspect_ratio?: string; // Aspect ratio for Imagen (e.g., "1:1", "16:9")
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

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
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
    process.env.GEMINI_CONTENT_MODEL || "gemini-2.0-flash-preview-image-generation";
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GOOGLE_API_KEY}`;

  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
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

  const response = await fetch("https://api.openai.com/v1/images/generations", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${OPENAI_API_KEY}`,
    },
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
      '  style   - Style preset: ' + Object.keys(STYLE_PRESETS).join(", ")
    );
    console.error("  count   - Number of variants (1-4, default: 1)");
    console.error('  negative - Negative prompt, e.g. "blurry, text"');
    console.error(
      '  aspect_ratio - Aspect ratio for Imagen, e.g. "1:1", "16:9"\n'
    );
    console.error("Environment variables:");
    console.error("  GOOGLE_AI_API_KEY   - Google AI key (Gemini/Imagen)");
    console.error("  OPENAI_API_KEY      - OpenAI key (DALL-E 3)");
    console.error(
      '  ASSET_GEN_PROVIDER  - "gemini" (default) or "openai"'
    );
    console.error(
      "  GEMINI_IMAGE_MODEL  - Imagen model (default: imagen-3.0-generate-001)"
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

  // Enhance prompt with style preset
  let prompt = basePrompt;
  if (options.style && STYLE_PRESETS[options.style]) {
    prompt = `${basePrompt}. Style: ${STYLE_PRESETS[options.style]}`;
  }
  if (options.negative) {
    prompt += `. Do NOT include: ${options.negative}`;
  }

  // Resolve output path
  const { fullPath, resPath } = resolveOutputPath(options.output, projectDir);
  mkdirSync(dirname(fullPath), { recursive: true });

  try {
    let images: Buffer[];
    if (PROVIDER === "openai") {
      images = await generateWithOpenAI(prompt, options);
    } else {
      images = await generateWithGemini(prompt, options);
    }

    // Save images
    const savedPaths: string[] = [];
    if (images.length === 1) {
      await Bun.write(fullPath, images[0]);
      savedPaths.push(resPath);
    } else {
      const ext = fullPath.substring(fullPath.lastIndexOf("."));
      const base = fullPath.substring(0, fullPath.lastIndexOf("."));
      const resBase = resPath.substring(0, resPath.lastIndexOf("."));
      const resExt = resPath.substring(resPath.lastIndexOf("."));
      for (let i = 0; i < images.length; i++) {
        const path = `${base}_${i}${ext}`;
        await Bun.write(path, images[i]);
        savedPaths.push(`${resBase}_${i}${resExt}`);
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
