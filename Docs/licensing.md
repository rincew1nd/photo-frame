# Licensing

Status: Draft v0.1
Related: [`architecture.md`](architecture.md), [`plugins.md`](plugins.md)

This is an engineering summary, not legal advice.

## 1. Application license

The application is licensed under the **MIT License**.

Required repository additions:

- root `LICENSE` with the MIT text;
- root `THIRD_PARTY_NOTICES.md` generated from the dependency and native-library set;
- `LICENSES/` directory for full third-party license texts;
- packaged notices in Windows/Linux/Android distributions.

## 2. License summary

| Component | License | Distribution notes |
|---|---|---|
| Flutter / Dart | BSD-3-Clause | Include notices |
| Riverpod, go_router, Dio, Drift, freezed, json_serializable, logging, path_provider, package_info_plus | Mostly MIT/BSD/Apache-2.0 | Generate a complete notice file |
| media_kit | MIT | Include notice |
| libmpv | LGPL-2.1+ (build dependent) | Pin an LGPL build; dynamic linking; notices/source offer |
| FFmpeg | LGPL-2.1+ or GPL (build dependent) | Use an LGPL-only build; avoid GPL codecs |
| webview_cef | Apache-2.0 | Include notice |
| CEF | BSD-style | Include CEF/Chromium third-party licenses |
| Chromium | BSD-style plus third-party licenses | Include `LICENSES.chromium.html` or equivalent |
| libheif | LGPL-3.0 | Planned Phase 3; dynamic linking; notices/source offer |
| libde265 | LGPL-3.0 | Planned Phase 3; dynamic linking; notices/source offer |
| dav1d | BSD-2-Clause | Planned Phase 3; include notice |
| LibRaw | LGPL-2.1 or CDDL-1.0 (alternative) | Planned Phase 3; choose LGPL-2.1; dynamic linking; notices/source offer |
| flutter_secure_storage | BSD-style | Include notice |
| webview_flutter | BSD-style | Include notice |
| local_auth, wakelock_plus, window_manager, launch_at_startup | Permissive (BSD/MIT/Apache-2.0) | Generate notices |
| Open-Meteo client data | Service terms | No API key; comply with provider terms |

Exact versions and licenses are pinned at scaffold time. The generated notice file is the
authoritative list.

## 3. LGPL compliance

libmpv, FFmpeg (LGPL build), libheif, libde265, and LibRaw are LGPL dependencies. To keep the MIT app
compliant:

- Link them dynamically (`.so`/`.dll`/Android shared libraries), not statically.
- Do not modify the libraries, or publish the modifications under the LGPL if you do.
- Include copyright/license notices in the application and installers.
- Provide the corresponding source for the exact library versions, or a valid written offer.
- Preserve the user's ability to replace the LGPL libraries where the platform permits.
- On Android, ship them as separate shared libraries; on desktop, bundle them as separate
  libraries.
- Do not add GPL-only FFmpeg parts (for example `--enable-gpl` codecs) unless the whole application
  is relicensed under the GPL.

## 4. FFmpeg / libmpv build policy

- Use LGPL builds only.
- Avoid GPL-only components such as `libx264`/`libx265` encoders unless the app is GPL.
- Decoders required by the product (H.264, HEVC, AV1, VP9, ProRes, common audio) are available in
  LGPL configurations, subject to the chosen build.
- Pin the build and record its configuration in `licensing.md`/build scripts.
- Media_kit’s bundled libmpv builds must be verified to be LGPL variants before release.
- If a codec requires a GPL component, omit it or obtain a different license; do not silently ship
  a GPL build.

## 5. CEF and Chromium

- CEF is BSD-licensed, but the binary distribution includes Chromium and third-party components
  under multiple licenses.
- Ship the CEF/Chromium license files with the app.
- `webview_cef` itself is Apache-2.0; preserve its NOTICE.
- CEF helper processes and resources must be included in the desktop package.
- Keep CEF updated for security; review release notes for licensing changes.

## 6. Native still decoders (planned Phase 3)

This is the planned Phase 3 dependency set. The libraries are not bundled yet; until they are, the app
falls back to Immich previews for HEIC/AVIF/RAW.

- libheif: LGPL-3.0. HEIC/AVIF container and decode API. Dynamic linking, notices, source offer.
- libde265: LGPL-3.0. HEVC/HEIC codec used by libheif. Dynamic linking, notices, source offer.
- dav1d: BSD-2-Clause. AV1/AVIF codec. Include the upstream notice.
- LibRaw: LGPL-2.1 (or CDDL-1.0 alternative). RAW (CR2/NEF/ARW/DNG/ProRAW). Choose LGPL-2.1; dynamic
  linking; include notice/source offer.
- Dynamic linking only: one shared library per decoder, never merged into the app binary, so the LGPL
  libraries can be replaced and the app relinked. Provide the corresponding source for the exact library
  versions or a valid written offer.
- Bundle the license/notice files with the eventual native libraries (`third_party/stills/licenses/`,
  copied to the packaged `licenses/` directory).
- x265 and AOM encoders are intentionally excluded; no encoding capability is added. Keep them out of
  every build script.
- ProRAW is a DNG variant processed through LibRaw; no Adobe SDK is required for the planned path.
  Validate support and document any limitations.

## 7. Patents and codecs

Copyright licenses do not grant patent licenses for codecs.

- HEVC/H.265, AVC/H.264, AV1, and Dolby technologies may have patent pools or licensing programs.
- The app does not claim Dolby Vision support; HDR10/HLG content is tone-mapped to SDR.
- Software decode on desktop and hardware decode on Android may have different patent
  implications.
- For personal/sideload use this is typically not pursued; for broad commercial distribution,
  obtain legal advice before shipping.
- Do not advertise codec support beyond the actual bundled decoder matrix.

## 8. Plugins

- Every plugin manifest declares a `license` field.
- Bundled example plugins are MIT, matching the app.
- User-installed plugins remain the responsibility of their authors; the app displays the declared
  license and installs only local ZIPs with explicit consent.
- No plugin may bundle GPL/native code through the plugin format (native binaries are rejected).

## 9. Release compliance checklist

- [ ] Root `LICENSE` present.
- [ ] `THIRD_PARTY_NOTICES.md` generated for all shipped packages and native libraries.
- [ ] CEF/Chromium license files included in desktop packages.
- [ ] LGPL source offer / source archive available for the exact library versions.
- [ ] Android shared-library linking verified.
- [ ] FFmpeg/libmpv builds verified LGPL-only.
- [ ] No GPL-only codecs or tools shipped.
- [ ] Plugin reference bundles declare MIT.
- [ ] HDR/Dolby claims reviewed; only SDR tone-mapping documented.
- [ ] App stores/distribution pages include license and patent disclaimers.
