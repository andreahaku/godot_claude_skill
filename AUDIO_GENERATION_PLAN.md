# Audio Generation Plan

## Purpose

This document proposes a dedicated audio-generation architecture for `godot_claude_skill`, with a strong focus on:

- usefulness for Godot game developers
- easy Claude integration
- clean asset-pipeline behavior
- safe iteration and regeneration
- a provider abstraction that can start with ElevenLabs and expand later

As of March 7, 2026, ElevenLabs officially documents product/API coverage for:

- Text to Speech
- Text to Dialogue
- Sound Effects
- Speech to Text
- Voice Design
- Voice Changer
- Music

This makes ElevenLabs a strong first provider for this project.

## Product Goals

The audio layer should help a Godot developer do five practical things well:

1. Generate placeholder and production-ready voice lines.
2. Generate sound effects and loopable ambiences quickly.
3. Import audio cleanly into Godot and wire it into scenes.
4. Preserve metadata so audio can be regenerated later.
5. Stay easy for Claude to use through a small number of reliable workflows.

## Non-Goals

At least initially, this system should not try to be:

- a full DAW
- a full dialogue authoring suite
- a general-purpose audio editing package
- a live voice-agent system

It should instead optimize for game-development workflows inside a Godot project.

## Recommended Scope

## Phase 1 scope

Start with the highest-value capabilities:

- voice line generation
- sound effect generation
- audio import and inspection
- scene wiring
- manifest generation

That means the first shipping commands should be:

- `generate_voice_line`
- `generate_sfx`
- `inspect_audio_asset`
- `attach_audio_asset`
- `create_audio_bus_if_missing`
- `create_audio_manifest`
- `regenerate_audio_asset`

## Phase 2 scope

Add workflow depth:

- dialogue packs
- subtitle timing
- transcription
- voice design previews
- randomized SFX groups

Commands:

- `generate_dialogue_pack`
- `transcribe_audio_asset`
- `create_voice_design_preview`
- `create_audio_randomizer`
- `generate_ambient_loop`

## Phase 3 scope

Add experimental/advanced capabilities:

- music generation
- voice conversion
- lip-sync export helpers
- localization-aware voice generation

Commands:

- `generate_music_track`
- `generate_music_loop`
- `convert_voice_asset`
- `export_dialogue_timing`
- `generate_localized_voice_lines`

## Why ElevenLabs Fits Well

ElevenLabs is a strong first provider because its official docs currently expose:

- TTS for voice lines
- Text to Dialogue for multi-speaker scripted dialogue
- Sound Effects for SFX and ambiences
- STT for transcripts and timestamps
- Voice Design for creating project-specific voices
- Music generation

For a Godot workflow, that covers most of the audio placeholders a developer wants during production.

## Important Product Caution

The official ElevenLabs docs currently show both:

- Music API reference endpoints such as `/v1/music`
- a capability page that still says public API access is "coming soon"

Because of that inconsistency, this project should treat music integration as `experimental` until verified in real use with target accounts/plans.

## Proposed Architecture

## High-level design

The audio feature should follow the same three-layer pattern as the image generator:

1. `skill/` layer for provider calls and file generation
2. Godot plugin commands for import/wiring/inspection
3. sidecar manifests for regeneration and traceability

## New skill-side files

Recommended additions:

- `skill/generate_audio.ts`
- `skill/audio_provider_elevenlabs.ts`
- `skill/audio_manifest.ts`
- `skill/audio_utils.ts`

Optional later:

- `skill/transcribe_audio.ts`
- `skill/design_voice.ts`

## Godot-side integration

The existing [audio_handler.gd](/Users/niccolo/Development/Godot/godot_claude_skill/godot-plugin/handlers/audio_handler.gd) should be extended rather than replaced.

Recommended command additions:

- `import_audio_asset`
- `get_audio_asset_info`
- `attach_audio_stream`
- `create_audio_randomizer`
- `create_voice_player`
- `create_ambient_player`
- `link_subtitle_resource`

If the handler gets too large, split out:

- `audio_asset_handler.gd`
- `dialogue_handler.gd`

## Provider abstraction

Do not hardcode ElevenLabs into the public command API.

Use a provider-neutral internal shape:

```ts
interface AudioProvider {
  generateVoiceLine(input: VoiceLineRequest): Promise<AudioGenerationResult>;
  generateSfx(input: SfxRequest): Promise<AudioGenerationResult>;
  transcribe?(input: TranscriptionRequest): Promise<TranscriptionResult>;
  generateDialogue?(input: DialogueRequest): Promise<AudioGenerationResult>;
  designVoice?(input: VoiceDesignRequest): Promise<VoiceDesignResult>;
  generateMusic?(input: MusicRequest): Promise<AudioGenerationResult>;
}
```

Then configure:

- `AUDIO_GEN_PROVIDER=elevenlabs`

This keeps the skill open to future providers.

## Recommended User-Facing Commands

## 1. `generate_voice_line`

Purpose:

- generate a single spoken line and save it into the Godot project

Example:

```bash
bun skill/generate_audio.ts voice_line \
  '{"text":"We need to move now!","output":"res://audio/voice/npc_guard_alert_01.mp3","project":"/path/to/project","provider":"elevenlabs","voice_id":"JBFqnCBsd6RMkjVDRZzb","model":"eleven_flash_v2_5","format":"mp3_44100_128"}'
```

Suggested request shape:

```json
{
  "type": "voice_line",
  "text": "We need to move now!",
  "output": "res://audio/voice/npc_guard_alert_01.mp3",
  "project": "/path/to/project",
  "provider": "elevenlabs",
  "voice_id": "JBFqnCBsd6RMkjVDRZzb",
  "model": "eleven_flash_v2_5",
  "language_code": "en",
  "format": "mp3_44100_128",
  "seed": 42,
  "voice_settings": {
    "stability": 0.4,
    "similarity_boost": 0.8,
    "style": 0.25,
    "use_speaker_boost": true
  },
  "tags": ["dialogue", "guard", "combat"]
}
```

## 2. `generate_sfx`

Purpose:

- generate a one-shot or loopable sound effect

Example:

```bash
bun skill/generate_audio.ts sfx \
  '{"text":"Short metallic sword impact with bright ring","output":"res://audio/sfx/sword_hit_01.mp3","project":"/path/to/project","provider":"elevenlabs","duration_seconds":1.2,"loop":false}'
```

Suggested request shape:

```json
{
  "type": "sfx",
  "text": "Short metallic sword impact with bright ring",
  "output": "res://audio/sfx/sword_hit_01.mp3",
  "project": "/path/to/project",
  "provider": "elevenlabs",
  "duration_seconds": 1.2,
  "loop": false,
  "prompt_influence": 0.45,
  "format": "mp3_44100_128",
  "tags": ["sfx", "combat", "sword"]
}
```

## 3. `generate_ambient_loop`

Purpose:

- a specialized SFX command for loopable ambient beds

Why separate it:

- better defaults
- avoids forcing the user to remember loop settings
- simpler prompting guidance

Suggested request shape:

```json
{
  "type": "ambient_loop",
  "text": "Night forest ambience with crickets and distant wind",
  "output": "res://audio/ambience/forest_night_loop.mp3",
  "project": "/path/to/project",
  "provider": "elevenlabs",
  "duration_seconds": 15,
  "loop": true,
  "prompt_influence": 0.35,
  "tags": ["ambience", "forest", "night"]
}
```

## 4. `generate_dialogue_pack`

Purpose:

- create multiple voice lines or a multi-speaker exchange together

Two modes:

- stitched single file
- separate files per line

Suggested request shape:

```json
{
  "type": "dialogue_pack",
  "project": "/path/to/project",
  "provider": "elevenlabs",
  "output_dir": "res://audio/dialogue/intro_scene",
  "lines": [
    {
      "id": "guard_001",
      "speaker": "guard",
      "voice_id": "voice_guard_id",
      "text": "Halt. State your business."
    },
    {
      "id": "hero_001",
      "speaker": "hero",
      "voice_id": "voice_hero_id",
      "text": "I'm here to see the captain."
    }
  ],
  "format": "mp3_44100_128",
  "create_subtitles": true
}
```

## 5. `transcribe_audio_asset`

Purpose:

- derive transcript and timings from existing project audio

Useful for:

- subtitle generation
- QA
- content search
- localization prep

Suggested request shape:

```json
{
  "type": "transcribe",
  "project": "/path/to/project",
  "provider": "elevenlabs",
  "input": "res://audio/voice/npc_guard_alert_01.mp3",
  "output": "res://audio/voice/npc_guard_alert_01.transcript.json",
  "diarize": false,
  "include_word_timestamps": true
}
```

## 6. `create_voice_design_preview`

Purpose:

- generate one or more voice previews from a textual voice description

Suggested request shape:

```json
{
  "type": "voice_design_preview",
  "provider": "elevenlabs",
  "voice_description": "Gruff middle-aged male city guard, stern but human, slight fatigue",
  "sample_text": "State your business and be quick about it.",
  "output_dir": "res://audio/voices/guard_preview"
}
```

## Godot Integration Commands

The skill-side generator should not stop at file creation. It should integrate with Godot cleanly.

## 1. `import_audio_asset`

Purpose:

- force a Godot rescan/reimport
- return the imported resource path and basic metadata

Suggested params:

```json
{
  "audio_path": "res://audio/sfx/sword_hit_01.mp3"
}
```

## 2. `get_audio_asset_info`

Purpose:

- inspect a Godot audio asset after import

Return:

- path
- stream type
- duration if available
- channel count if available
- loop flag if available
- file size
- linked manifest path if present

## 3. `attach_audio_stream`

Purpose:

- assign an imported audio stream to an audio player node

Suggested params:

```json
{
  "node_path": "Player/JumpSfx",
  "audio_path": "res://audio/sfx/jump_01.mp3",
  "bus": "SFX",
  "autoplay": false
}
```

## 4. `create_audio_randomizer`

Purpose:

- build a `AudioStreamRandomizer` resource from multiple generated files

This is high value for games because many SFX need variation:

- footsteps
- impacts
- menu clicks
- creature sounds

## 5. `create_voice_player`

Purpose:

- create and configure a voice playback node with sensible defaults

Defaults:

- node type `AudioStreamPlayer2D` or `AudioStreamPlayer`
- bus `Voice`
- no autoplay

## 6. `create_ambient_player`

Purpose:

- create a loop-ready ambient playback setup

Defaults:

- bus `Ambience`
- looping stream
- optional random start offset if supported

## Recommended Manifest Format

Every generated audio file should have a sidecar JSON file.

Example:

- `npc_guard_alert_01.mp3`
- `npc_guard_alert_01.audio.json`

## Manifest schema

```json
{
  "version": 1,
  "type": "voice_line",
  "provider": "elevenlabs",
  "created_at": "2026-03-07T12:34:56Z",
  "source": {
    "text": "We need to move now!",
    "negative": null,
    "voice_id": "JBFqnCBsd6RMkjVDRZzb",
    "model": "eleven_flash_v2_5",
    "language_code": "en",
    "seed": 42,
    "voice_settings": {
      "stability": 0.4,
      "similarity_boost": 0.8,
      "style": 0.25,
      "use_speaker_boost": true
    }
  },
  "output": {
    "asset_path": "res://audio/voice/npc_guard_alert_01.mp3",
    "manifest_path": "res://audio/voice/npc_guard_alert_01.audio.json",
    "format": "mp3_44100_128",
    "duration_seconds": 1.48,
    "mime_type": "audio/mpeg"
  },
  "godot": {
    "bus": "Voice",
    "attached_nodes": [
      "NPCGuard/VoicePlayer"
    ],
    "imported": true
  },
  "tags": [
    "dialogue",
    "guard",
    "combat"
  ],
  "usage": {
    "license_note": "Check ElevenLabs plan/music terms where applicable",
    "request_id": "provider_request_id_if_available"
  },
  "regeneration": {
    "regenerates": null,
    "history": []
  }
}
```

## Why manifests are essential

Without manifests, generated audio quickly becomes unmanageable:

- nobody knows which prompt created a file
- regeneration becomes guesswork
- voice settings are lost
- bus and node wiring is undocumented
- subtitles cannot be regenerated reliably

## ElevenLabs API Mapping

This section maps repo features to the official ElevenLabs surface.

## 1. Text to Speech

Best use:

- single voice lines
- NPC barks
- narration
- menu voiceover
- accessibility voice features

Official docs indicate:

- endpoint: `POST /v1/text-to-speech/:voice_id`
- request requires `text`
- supports `model_id`
- supports `language_code`
- supports `voice_settings`
- supports `seed`
- supports multiple output formats

Recommended repo use:

- default to `eleven_flash_v2_5` for low-latency placeholder generation
- allow `eleven_multilingual_v2` for more stable long-form
- expose model choice explicitly

## 2. Text to Dialogue

Best use:

- multi-character conversations
- cutscene exchanges
- radio chatter

Official docs indicate:

- dedicated Text to Dialogue support
- based on `eleven_v3`
- accepts multiple dialogue inputs with text + voice IDs
- supports up to 10 unique voice IDs
- is not intended for real-time applications

Recommended repo use:

- expose as batch/offline generation only
- encourage “generate several options and choose one”
- mark as slower and more variable than single-line TTS

## 3. Sound Effects

Best use:

- one-shot SFX
- loopable ambience
- creature sounds
- UI sounds

Official docs indicate:

- endpoint: `POST /v1/sound-generation`
- request requires `text`
- optional `loop`
- optional `duration_seconds`
- optional `prompt_influence`
- default model `eleven_text_to_sound_v2`

Recommended repo use:

- make this the first audio-generation feature after voice lines
- add specialized commands for one-shot and ambient-loop workflows

## 4. Speech to Text

Best use:

- subtitle generation
- transcript extraction
- dialogue searchability
- timing metadata

Official docs indicate:

- Scribe models support 90+ languages
- word-level timestamps
- speaker diarization
- dynamic audio tagging
- realtime STT via WebSockets is also available

Recommended repo use:

- start with offline transcription only
- export subtitle-friendly JSON
- optionally export `.srt` or `.vtt` later

## 5. Voice Design

Best use:

- project-specific NPC voice previews
- quick voice palette exploration

Official docs indicate:

- endpoint: `POST /v1/text-to-voice/design`
- returns preview clips plus generated voice IDs

Recommended repo use:

- add preview-only support first
- do not over-automate permanent voice creation until account/plan behavior is better understood

## 6. Music

Best use:

- placeholder soundtrack
- menu music
- ambient beds
- quick prototyping

Official docs indicate:

- API reference endpoints exist for `POST /v1/music` and streaming variants
- prompt or composition plan supported
- `music_length_ms`
- `force_instrumental`
- `respect_sections_durations`
- `sign_with_c2pa`

Product caution:

- the overview docs still contain wording that public API access is "coming soon"

Recommended repo use:

- mark music generation as `experimental`
- ship later than TTS/SFX
- prefer instrumental generation first

## Recommended Defaults

## Voice lines

Default choices:

- provider: `elevenlabs`
- model: `eleven_flash_v2_5`
- format: `mp3_44100_128`
- bus: `Voice`
- manifest: on
- attach subtitles: optional

## SFX

Default choices:

- provider: `elevenlabs`
- model: `eleven_text_to_sound_v2`
- format: `mp3_44100_128`
- bus: `SFX`
- manifest: on

## Ambient loops

Default choices:

- loop: true
- duration: 10-20 seconds
- bus: `Ambience`
- prompt influence: 0.3 to 0.4

## Dialogue packs

Default choices:

- separate files per line
- subtitle JSON generated
- shared scene metadata generated

## File Layout Recommendation

Use stable folder conventions:

```text
res://audio/
res://audio/voice/
res://audio/dialogue/
res://audio/sfx/
res://audio/ambience/
res://audio/music/
res://audio/manifests/
res://audio/subtitles/
```

Manifest options:

- colocated next to audio file
- centralized in `res://audio/manifests/`

Recommended default:

- colocated next to the file

This keeps each generated asset self-contained.

## Godot Resource Strategy

Do not stop at raw `.mp3` or `.wav` files.

When helpful, auto-create Godot resources:

- `AudioStreamRandomizer` for SFX groups
- `Resource` or JSON subtitle assets for dialogue
- scene-local players for quick integration

Useful future helper commands:

- `create_footstep_set`
- `create_impact_variation_set`
- `create_dialogue_bundle`

## Suggested Command Workflows

## Workflow A: Generate and wire a jump SFX

1. `generate_sfx`
2. `import_audio_asset`
3. `create_audio_bus_if_missing` for `SFX`
4. `attach_audio_stream` to `Player/JumpSfx`
5. save manifest with linked node info

## Workflow B: Generate an NPC bark

1. `generate_voice_line`
2. `import_audio_asset`
3. `create_audio_bus_if_missing` for `Voice`
4. `create_voice_player`
5. `attach_audio_stream`
6. optionally `transcribe_audio_asset` for subtitles

## Workflow C: Generate dialogue for a cutscene

1. `generate_dialogue_pack`
2. create per-line manifests
3. create subtitle JSON
4. optionally create a scene helper resource mapping line IDs to files

## Workflow D: Generate ambient forest loop

1. `generate_ambient_loop`
2. `import_audio_asset`
3. `create_ambient_player`
4. assign to `Ambience`

## Skill UX Recommendations

Claude should not need to memorize provider-specific details most of the time.

Good defaults:

- infer bus from asset type
- infer output directory from asset type
- create manifest automatically
- import automatically
- return next suggested Godot command

Good response shape:

```json
{
  "success": true,
  "asset_path": "res://audio/sfx/jump_01.mp3",
  "manifest_path": "res://audio/sfx/jump_01.audio.json",
  "provider": "elevenlabs",
  "type": "sfx",
  "duration_seconds": 0.92,
  "suggested_next": [
    {
      "command": "attach_audio_stream",
      "params": {
        "node_path": "Player/JumpSfx",
        "audio_path": "res://audio/sfx/jump_01.mp3",
        "bus": "SFX"
      }
    }
  ]
}
```

## Implementation Strategy

## Step 1: new Bun generator

Create `skill/generate_audio.ts`.

Responsibilities:

- parse command type and options
- validate project path
- call provider layer
- save audio to disk
- write manifest
- optionally write transcript/subtitle files
- return JSON summary

## Step 2: ElevenLabs provider module

Create `skill/audio_provider_elevenlabs.ts`.

Responsibilities:

- call ElevenLabs REST endpoints with `fetch`
- set `xi-api-key`
- normalize outputs
- map provider responses to repo-level result objects

Why use raw `fetch` instead of SDK first:

- no new dependency required
- consistent with current image generator style
- easier to keep Bun-native

## Step 3: manifest module

Create `skill/audio_manifest.ts`.

Responsibilities:

- generate manifest
- update regeneration history
- locate colocated manifest path
- merge Godot attachment info later

## Step 4: Godot audio import/wiring commands

Extend [audio_handler.gd](/Users/niccolo/Development/Godot/godot_claude_skill/godot-plugin/handlers/audio_handler.gd).

Responsibilities:

- reimport audio files
- inspect streams
- attach streams to nodes
- create players and randomizers
- update manifest linkage if desired

## Step 5: subtitle/transcript support

Add:

- STT-based transcript export
- JSON subtitle format
- optional `.srt` or `.vtt` export

## Step 6: dialogue and music

Ship later behind maturity labels:

- `beta` for dialogue
- `experimental` for music

## Recommended Environment Variables

Add:

- `ELEVENLABS_API_KEY`
- `AUDIO_GEN_PROVIDER`
- `AUDIO_GEN_DEFAULT_FORMAT`
- `AUDIO_GEN_DEFAULT_VOICE_MODEL`
- `AUDIO_GEN_DEFAULT_SFX_MODEL`

Optional:

- `AUDIO_GEN_OUTPUT_DIR`
- `AUDIO_GEN_MANIFESTS`

## Error Handling

The audio toolchain should use explicit machine-readable errors.

Recommended error codes:

- `NO_API_KEY`
- `UNSUPPORTED_PROVIDER`
- `INVALID_AUDIO_TYPE`
- `INVALID_OUTPUT_PATH`
- `PROJECT_NOT_FOUND`
- `PROVIDER_AUTH_ERROR`
- `PROVIDER_RATE_LIMIT`
- `PROVIDER_VALIDATION_ERROR`
- `AUDIO_WRITE_ERROR`
- `MANIFEST_WRITE_ERROR`
- `IMPORT_ERROR`
- `NODE_NOT_FOUND`
- `WRONG_NODE_TYPE`

## Maturity Labels

Recommended launch labels:

- `generate_voice_line`: `stable`
- `generate_sfx`: `stable`
- `generate_ambient_loop`: `stable`
- `transcribe_audio_asset`: `beta`
- `generate_dialogue_pack`: `beta`
- `create_voice_design_preview`: `beta`
- `generate_music_track`: `experimental`

## Recommended First Milestone

If the goal is to ship the highest-value version first, implement this exact slice:

1. `skill/generate_audio.ts`
2. ElevenLabs TTS support
3. ElevenLabs SFX support
4. `.audio.json` manifests
5. Godot import command
6. Godot attach command
7. Godot create-randomizer command

This alone would already make the project much more powerful for real Godot work.

## Proposed Source Links

Official ElevenLabs sources used for this plan:

- API overview: https://elevenlabs.io/api
- API reference intro: https://elevenlabs.io/docs/api-reference
- TTS capability docs: https://elevenlabs.io/docs/overview/capabilities/text-to-speech
- TTS endpoint: https://elevenlabs.io/docs/api-reference/text-to-speech/convert
- Text to Dialogue capability docs: https://elevenlabs.io/docs/overview/capabilities/text-to-dialogue
- Dialogue endpoint docs: https://elevenlabs.io/docs/api-reference/text-to-dialogue/convert
- Sound effects capability docs: https://elevenlabs.io/docs/capabilities/sound-effects
- Sound effects endpoint: https://elevenlabs.io/docs/api-reference/text-to-sound-effects/convert
- STT capability docs: https://elevenlabs.io/docs/overview/capabilities/speech-to-text
- Realtime STT docs: https://elevenlabs.io/docs/api-reference/speech-to-text/
- Voice design endpoint: https://elevenlabs.io/docs/api-reference/text-to-voice/design
- Music overview: https://elevenlabs.io/docs/overview/capabilities/music
- Music endpoint: https://elevenlabs.io/docs/api-reference/music/compose
