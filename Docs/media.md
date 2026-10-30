# Media Pipeline

Status: Draft v0.1
Related: [`architecture.md`](architecture.md), [`data-cache.md`](data-cache.md),
[`plugins.md`](plugins.md)

## 1. Goals

- Play original Immich photos, videos, Live Photos, and animated GIFs with audio.
- Support the common original codecs without relying on Immich transcodes.
- Keep 24/7 playback stable and memory-bounded.
- Apply per-aspect image fit, Live Photo mode, and pan strength.
- Degrade gracefully when a codec, file, or server is unavailable.

## 2. Playback pipelines

### Video and Live Photo motion

- Engine: `media_kit` with libmpv/FFmpeg.
- Sources: local cached original file first, then the Immich original URL with `x-api-key`
  headers. No API key in URLs.
- Hardware decode: enabled where available; automatic fallback to software.
- Audio: decoded by libmpv; mute/volume follows app state. No HTML5 autoplay restrictions.
- Live Photo: the still is displayed, then the associated motion video is played with its audio.
  Modes: Off (still only), Live (play once, then still), Loop (repeat while the slide is visible),
  Bounce (forward, then a reverse pass made of single-frame `frame-back-step` commands while the
  slide is visible; audio is silent during the reverse pass, and it falls back to forward looping
  when frame stepping is unavailable). Reverse stepping is slower and choppier than forward
  playback.
- Video duration controls the slide duration; the slideshow advances on end.
- Progress, pause/resume, mute/unmute, next/previous are domain actions; they do not depend on
  player-specific UI.

### Still images

- Flutter/Skia codecs: JPEG, PNG, GIF (animated), WebP, BMP.
- libheif: HEIC/HEIF, AVIF.
- LibRaw: DNG and ProRAW only.
- Unsupported still formats fall back to the Immich preview (JPEG/WebP). The app logs the fallback
  and continues; it does not crash.
- Animated GIFs are decoded by Flutter at display resolution and cached as originals. Large GIFs
  are bounded by cache and decode-size limits.
- Animated WebP/AVIF/HEIC are not a v1 requirement; display the first frame or use the Immich
  preview if decoding is unsupported.

### Exotic originals

“Any original” is bounded by the pinned FFmpeg/libheif/LibRaw build, not by an unbounded format
promise. If libmpv cannot decode a video, the app may use the Immich browser-compatible playback
stream as a last resort and record it in diagnostics.

## 3. HDR policy

HDR/10-bit content is decoded and tone-mapped to SDR:

- Video: mpv tone-mapping to SDR; configurable target peak; HDR10/HLG handled; HDR10+ dynamic
  metadata is ignored; Dolby Vision is not supported (base layer/tone-map at best).
- Stills: 10-bit HEIC/AVIF and 16-bit DNG/ProRAW are tone-mapped to sRGB 8-bit for display and
  cache.
- Plugins and app controls are SDR.
- The app must not advertise “HDR output” or “Dolby Vision.”
- True HDR output would require a per-platform native video surface (Android SurfaceView, native
  mpv on desktop) and HDR-aware plugin composition. It is explicitly out of scope for v1.

## 4. Still-image decoding and cache

### Decode rules

- Never decode a full RAW image on the UI thread.
- For HEIC/AVIF/DNG/ProRAW:
  1. Show the embedded preview when available.
  2. Decode the full image in an isolate or native worker.
  3. Downscale to display resolution plus pan headroom.
  4. Tone-map/convert to sRGB 8-bit.
  5. Cache the display-sized image; keep the original for future re-renders.
- Decode size target: viewport longest side multiplied by a small pan headroom (default 1.5x),
  capped by a memory budget. This prevents 50 MP originals from allocating hundreds of megabytes.
- ProRAW uses Apple’s DNG variant; LibRaw may not reproduce Apple’s local tone mapping exactly.
  Use the embedded preview or a documented fallback if the render is unacceptable.
- Color: use the source ICC/color profile where available; convert to sRGB; no wide-gamut/HDR
  output.

### Cache formats

- Common photos may be displayed directly from the original where Flutter can decode them.
- Converted stills are stored as display-sized JPEG/WebP (quality configured for visual fidelity),
  not as full RGBA.
- Animated GIFs stay as originals.
- Derived images are invalidated when the original checksum or display profile changes.

## 5. Supported format matrix

| Media | Pipeline | Notes |
|---|---|---|
| JPEG, PNG, WebP, BMP | Flutter | Direct or display-sized decode |
| GIF (animated) | Flutter | Preserve animation; bound memory |
| HEIC/HEIF | libheif | Tone-map 10-bit to sRGB; embedded preview first |
| AVIF | libheif | Same as HEIC |
| DNG | LibRaw | Display-sized SDR cache |
| ProRAW (DNG) | LibRaw | Validate quality; embedded preview fallback |
| H.264 | libmpv/FFmpeg | Hardware where available |
| HEVC/H.265 | libmpv/FFmpeg | Hardware where available; software fallback |
| AV1 | libmpv/FFmpeg | Hardware or dav1d/software; performance varies |
| VP9 | libmpv/FFmpeg | Software or hardware |
| MPEG-4/MPEG-2 | libmpv/FFmpeg | Software |
| ProRes/DNxHD | libmpv/FFmpeg | Software; performance depends on hardware |
| AAC, Opus, Vorbis, FLAC, AC-3/E-AC-3, DTS | libmpv/FFmpeg | Audio output; no bitstream passthrough in v1 |
| Unsupported still | Immich preview fallback | Logged |
| Unsupported/corrupt video | Immich playback stream or skip | Logged; never crash |

Other camera RAW formats (CR2/CR3/NEF/ARW/etc.) are not required for v1. TIFF and other still
formats are not promised; use the Immich preview fallback.

## 6. Display rules

- Image fit: Contain or Cover, per effective aspect profile, and authoritative.
- Contain always shows the whole image and disables Ken Burns; Cover fills the frame.
- Pan applies only with Cover: pan strength greater than zero enables Ken Burns pan/zoom when
  image motion is on, zero disables animation.
- Aspect buckets: 1:1, 4:3, 3:2, 16:9, Panorama; orientation-neutral classification with a 5%
  tolerance around the named ratios, otherwise the nearest named bucket, as defined by AR-01..AR-07.
- Unknown/invalid dimensions: remain Other, always shown, and use the Default profile.
- Transitions: configurable; transitions must not block the next slide.
- Per-aspect profile: image fit applies to photos, Live Photos, and videos; Live Photo mode only to
  Live Photos; pan strength only to photo imagery.
- Video fills the frame according to the effective profile; controls/progress are app UI.
- Safe areas/insets are respected on Android; desktop uses the viewport.

## 7. Audio

- Video and Live Photo motion audio is routed through libmpv.
- Mute/unmute is a global app setting; audio starts muted or per settings.
- Android audio focus is handled when playback starts/stops; no background playback in v1.
- The slideshow can run muted; Live Photo audio follows the same mute state.

## 8. Performance targets

| Target | Budget |
|---|---|
| Photo transition | No dropped frames during a 1 Hz plugin update |
| Video | 1080p30 on Android reference device; 4K on x64 when hardware decode supports it |
| Plugin overlay | 1 Hz state; low-rate OSR; no full-screen 4K transparent webview on Linux |
| Image decode | Off the UI thread; display-sized cache; RAW decode time measured and logged |
| Memory | Bounded image cache; one active player; disposed players on slide change |
| Startup | Slideshow starts before plugins finish initialising (NFR-01) |

## 9. Fallbacks and error handling

- Local cache miss → Immich original request with headers.
- Network failure → cached originals; if none, show the no-items state.
- Codec failure → Immich preview/playback stream or skip with diagnostics.
- Missing Live Photo video → show the still.
- Missing dimensions → never filter; use Default profile.
- Corrupt cache entry → delete and re-download; never crash.
- Storage full → stop prefetch, keep current media, surface a diagnostic.

## 10. Test fixtures

- H.264 + AAC MP4/MOV.
- HEVC 10-bit HDR10 and HLG samples.
- AV1 sample.
- HEIC 8-bit and 10-bit.
- AVIF.
- DNG and a ProRAW sample.
- Animated GIF.
- Live Photo pair (still + motion MOV).
- Corrupt/truncated files.
- A file with missing dimensions.
- Small local files only; no huge fixtures in the repository.

Tests verify decode, tone-mapping, audio, auto-advance, pause/resume, mute, per-aspect profiles,
unknown-dimension handling, and fallbacks.

## 11. Known limitations

- No true HDR output; no HDR10+ dynamic metadata; no Dolby Vision.
- No wide-gamut output; stills are cached as 8-bit sRGB.
- ProRAW rendering may not match Apple’s processing exactly.
- Software decode of high-bitrate 4K video can stutter on low-end hardware.
- Linux CEF overlay performance is constrained by software readback; plugins are kept small.
- Android plugin support depends on the system WebView version.
