# Debrify on LG webOS — `.ipk` packaging plan

Status: **research + plan — currently BLOCKED on hardware.** No app code in this branch. The
Flutter-version-skew question has been measured (§6). The available TV runs **webOS 25**, and
`flutter-webos` requires webOS 26+, so Phase 0 cannot start yet. See §8.

---

## 1. Verdict

Shipping Debrify as a webOS `.ipk` is **feasible via LG's official native Flutter SDK**
(`flutter-webos`), not via Flutter Web. The engine is a real Flutter embedder on ARM Linux, so
`dart:io`, the 75 files that import it, and the whole storage/services layer survive unchanged.

Two things make it a bigger job than "add a build target":

1. **`media_kit` will not come along.** The in-app player has to be rebuilt on
   `video_player_webos`, which has a materially smaller API surface (no track selection, no
   `httpHeaders`, no `setVolume`).
2. **Distribution is the weak link.** Developer Mode sideload with periodic session renewal is
   the only realistic channel; the LG Content Store is a non-starter for this app category and
   webOS 26 currently breaks the community root path.

Recommended shape: a **TV-profile build** — Discover / Debrify TV / Stremio TV / IPTV / cloud
browsing / playback — explicitly *not* a port of downloads, recording, or the desktop surface.

---

## 2. The two routes, and why we pick the native one

### Route A — `flutter-webos` native embedder ✅ chosen

LG ships an official Flutter SDK fork: <https://github.com/lg-flutter-webos/flutter-webos>.
It cross-compiles the real Flutter engine against a webOS NDK and emits an `.ipk` directly:

```
build/webos/{arch}/{mode}/ipk/{id}_{version}_{arch}.ipk
```

`flutter-webos run -d <device>` builds, packages, installs and launches in one step, with hot
reload and DevTools over the Developer Mode SSH port (9922).

Why it wins: it is a normal Flutter target. `dart:io`, sqflite, `path_provider`,
`shared_preferences`, `http`, isolates and the pure-Dart crypto stack all behave as they do on
Linux desktop. Our existing D-pad focus work carries over.

### Route B — Flutter Web wrapped in a webOS web app ❌ rejected

Package `flutter build web` output with `ares-package`. Reaches older TVs (webOS 6.0 =
Chromium 79, 22 = 87, 23 = 94, 24 = 108), but:

- `dart:io` is unavailable — 75 files and effectively the entire services layer would need a
  parallel web implementation. `web/` in this repo is still untouched Flutter boilerplate
  (`"description": "A new Flutter project."`), so the web target has never once been exercised.
- The HTML renderer is gone in modern Flutter; CanvasKit on TV-class SoCs is the known pain
  point, with LG's own forum carrying reports of large regressions after moving off the HTML
  renderer.
- CORS would block direct calls to Real-Debrid / TorBox / Premiumize / AllDebrid from the app
  origin, forcing a bundled Node.js JS service purely as a proxy.

Route B is only worth revisiting if reaching webOS ≤25 becomes a hard requirement, and then as
a separate, much thinner "remote + browse" app rather than a Debrify port.

---

## 3. Hard constraints to accept up front

| Constraint | Detail | Consequence |
|---|---|---|
| **Minimum OS** | `flutter-webos` supports **webOS 26 "Re:New" and above**. `video_player_webos` says "webOS 26 media or above". | No 2021-or-earlier TVs, ever. |
| **Reach over time** | webOS 26 began rolling out ~Aug 2026 starting with the 2025 G5 OLED, cascading to C-series, premium LCD and B-series, with 2024/2023/2022 sets scheduled late 2026 → early 2027. | Reach is small today and grows for ~a year. Ship when the audience exists. |
| **Host OS** | Ubuntu 22.04 / 24.04 / 26.04 only. | Fine for CI (`ubuntu-latest`); contributors on macOS/Windows need WSL2 or a devcontainer. |
| **Toolchain** | webOS NDK `starfish-x86_64-ca9v1`, target triple `webosmllib32-linux-gnueabi` → **32-bit ARM (armv7, Cortex-A9 baseline)**. ares CLI ≥ 3.2.4, which itself needs Node **14.15.1–16.20.2**. | Any native lib we bundle must be cross-compiled armhf. Node version pin conflicts with our normal tooling — isolate it. |
| **Flutter version skew** | `flutter-webos` is pinned to **Flutter 3.38.10** (`bin/internal/flutter.version` = `c6f67dede3…`). Debrify CI builds on **3.44.8**. | **Measured — not a blocker.** 18 analyzer errors across 6 files. See §6. |
| **Rendering** | Skia by default; Impeller is opt-in via `webos/meta/flutter-conf.json` → `engine-switches.enable-impeller`. | A perf lever to test, not a default. |
| **Luna access** | Every Luna Service call is gated by ACG groups declared in the app's permission config; bridged through `webos_service_bridge`. | Anything beyond the default grants needs an explicit ACG declaration. |

### Distribution — read this before committing engineering time

- **LG Content Store**: requires Seller Lounge onboarding and LG app review. A torrent-search /
  debrid client will not pass. Treat as unavailable.
- **Developer Mode sideload**: works, and is what `flutter-webos run` uses. But Developer Mode
  revokes elevated access 50 hours after activation and the session needs renewal (~1000h via
  Device Manager). Users must re-extend, and Dev Mode apps can be removed by the TV.
- **webosbrew Homebrew Channel**: the usual persistent sideload route, but it is **currently
  broken on webOS 26** — installation fails with a permission error
  (webosbrew/webos-homebrew-channel#234, reported Mar 2026, no fix landed).

So the honest user story today is: *"enable Developer Mode, sideload the `.ipk`, re-extend the
session periodically."* That is a real barrier and should be stated plainly in the README rather
than discovered by users.

---

## 4. Plugin gap analysis

Available webOS implementations (<https://github.com/lg-flutter-webos/plugins>) map onto our
dependency list better than expected.

### Covered — swap in the `_webos` sibling, same pattern as our `tvos:` siblings in `pubspec.yaml`

| Debrify dependency | webOS plugin | Notes |
|---|---|---|
| `shared_preferences` | `shared_preferences_webos` | Unblocks `services/storage_service.dart` wholesale — settings, continue-watching, favourites, provider toggles. |
| `sqflite` | `sqflite_webos` | Covers `debrify_tv_database.dart`, `iptv_catalog_db.dart`, `iptv_media_store.dart`, the profiles DB. |
| `path_provider` | `path_provider_webos` | |
| `video_player` | `video_player_webos` | See §5 — the big one. |
| `connectivity_plus` | `connectivity_plus_webos` | |
| `device_info_plus` | `device_info_plus_webos` | Backs `SecretVault`'s hardware-id key derivation. |
| `package_info_plus` | `package_info_plus_webos` | |
| `url_launcher` | `url_launcher_webos` | Opens the webOS browser app; verify our OAuth/device-code flows still read acceptably. |

Also available and worth adopting: `flutter_secure_storage_webos` (a better home for the
credential vault than a device-id-derived key), `webos_service_bridge` (Luna), `webos_display`,
`gamepads_webos`, `webos_app_manager`.

### Not covered — each needs a decision

| Dependency | Used by | Decision |
|---|---|---|
| `media_kit` / `media_kit_video` / `media_kit_libs_video` | `screens/video_player_screen.dart` (85 call sites), `utils/media_kit_init.dart`, subtitle auto-sync, audio feature tap | **Cut on webOS.** `media_kit_video`'s Linux implementation targets the GTK embedder's texture registrar, which the webOS embedder does not provide; libmpv would additionally need an armhf cross-build. Rebuild on `video_player_webos`. |
| `background_downloader` | `services/download_service.dart` | **Cut.** Drop local downloads from the TV profile. |
| `permission_handler` | storage/notification prompts | **Cut.** webOS uses ACG, not runtime permission dialogs. |
| `file_picker`, `saf_stream` | local file import, Android SAF | **Cut.** No local file browsing in the TV profile. |
| `android_intent_plus`, `flutter_sharing_intent`, native downloader channel | Android-only paths | Already `Platform.isAndroid`-gated — confirm none leak. |
| `window_manager` | desktop window sizing | Must be gated off — see §6, this is the dangerous one. |
| `wakelock_plus` | keeping the screen alive during playback | **Verify.** May be unnecessary: the webOS media pipeline generally suppresses the screensaver during playback. If not, a Luna call via `webos_service_bridge`. |
| `screen_brightness`, `volume_controller` | player HUD gestures | **Cut.** TV owns both; `setVolume` is unsupported by `video_player_webos` anyway. |
| `sqlite3` / `sqlite3_flutter_libs` (FFI) | direct FFI paths alongside sqflite | **Verify** whether any code path needs FFI sqlite rather than `sqflite`; if so it needs an armhf build. |
| `pug_flutter` | `services/analytics_service.dart` | **Verify** — pulls native code transitively. Likely needs stubbing. |
| `app_links` | deep links | **Cut** for v1; revisit via Luna launch parameters. |

Pure-Dart and therefore safe: `http`, `intl`, `path`, `archive`, `yaml`, `xml`, `crypto`,
`cryptography`, `collection`, `synchronized`, `provider`, `animations`, `google_fonts`,
`cached_network_image` / `flutter_cache_manager` (both ride on `path_provider`).

---

## 5. The player rebuild — the real cost centre

`video_player_webos` renders on a **dedicated hardware video plane** beneath a transparent
Flutter surface (requires `"transparent": true` in `appinfo.json`). This is the right
architecture for a TV — hardware decode, DRM support via `video_player_drm` — but it is not
media_kit, and the delta is where the work is.

Documented limitations, each mapped to what we lose:

| Limitation | What it costs Debrify |
|---|---|
| **No embedded audio/subtitle track enumeration or selection** in the supported-API table (only `setClosedCaptionFile` for external subtitle files) | The largest gap. `video_player/widgets/tracks_sheet.dart`, `_restoreTrackPreferences`, `_applyDefault*Language`, and `media_kit_subtitle_auto_sync.dart` all assume media_kit's track API. Multi-audio MKVs would play with whatever track the pipeline picks. **Verify against a real device before scoping** — the table may lag the implementation. |
| **`httpHeaders` unsupported** on `.network()` / `.networkUrl()` | `services/video_player_launcher.dart` accepts and forwards `httpHeaders`, and `iptv_catalog_db.dart` persists per-channel headers. IPTV sources that need `User-Agent`/`Referer` would break. **Workaround: a loopback `HttpServer` (dart:io) that proxies the stream and injects headers.** No such server exists in the codebase today — this is new code. |
| **`setVolume` unsupported** (throws `unsupported`) | Remove the player's volume gesture/HUD on webOS; defer to the TV remote. |
| **Max 5 concurrent players**; a 6th evicts the least-recently-created, which gets `error` code `-1` ("num of pipelines") | Matters for Stremio TV / Debrify TV channel surfing and trailer backdrops. Needs an explicit controller lifecycle audit — `widgets/hero_trailer_backdrop.dart` plus the tuner surf paths. |
| **`mixWithOthers` unsupported** | Trailer audio and player audio cannot overlap. Probably already the desired behaviour. |

Practical approach: introduce a **player abstraction** rather than forking the 8k-line
`video_player_screen.dart`. Define the narrow interface the screen actually needs (load, play,
pause, seek, speed, position/buffer streams, track list, subtitle load) with a media_kit backend
and a `video_player` backend, and have the webOS build select the latter. The tracks sheet then
degrades to whatever the backend reports rather than being conditionally compiled out. This is
worth doing regardless of webOS — it is also the missing piece behind the tvOS media_kit
scaffolding.

---

## 6. The `Platform.isLinux` trap

**webOS is Linux.** `Platform.operatingSystem` on the flutter-webos embedder is expected to
report `"linux"` — *verify this first, on device, before anything else.* If it does, every
desktop branch in the app lights up on a television:

- 285 `Platform.is*` call sites across `lib/`
- `main.dart` has at least six `Platform.isWindows || Platform.isLinux` branches (lines ~294,
  299, 304, 523, 733) driving `window_manager` setup, desktop sizing and `sqflite_common_ffi`
  initialisation
- `services/desktop_recording_service.dart` gates on `isMacOS || isWindows || isLinux`
- `PlatformUtil.supportsSubtitleAutoSync` returns true for `Platform.isLinux`
- `dev/scripts/bundle_linux_mpv.sh` assumptions do not apply

**Action, and this is step one of the whole port:** add `PlatformUtil.isWebOS` (detected from a
build-time define set by the webOS build, not from `Platform.operatingSystem` alone), make
`PlatformUtil.isTelevision` return true for it, and audit every `Platform.isLinux` site for
whether it means "desktop Linux" or "any Linux". Given the file already carries careful doc
comments about exactly this class of bug on tvOS (`Platform.isIOS` being true on Apple TV), the
pattern to follow is established — this is the same mistake one platform over.

### Flutter version skew — MEASURED

`flutter-webos` is pinned to **Flutter 3.38.10**; we build on **3.44.8**. This has now been
measured rather than guessed, by installing 3.38.10 and running the analyzer against this repo.

**Confirmation of the pin.** Flutter 3.38.10's release hash is `c6f67dede3` with Dart 3.10.9 —
byte-for-byte the revision in `flutter-webos/bin/internal/flutter.version` and the version banner
in LG's getting-started doc. The pin is exactly stable 3.38.10, not a fork.

**Dependency resolution: clean.** `flutter pub get` succeeds on 3.38.10 with only 6 dependency
downgrades and no resolution failure. The `google_fonts ^8.2.1` constraint that `pubspec.yaml`
warns about for 3.44 causes no trouble going backwards.

**Analyzer: 18 errors in `lib/`, across 6 files, in 3 API families.** All are Flutter framework
APIs that exist in 3.44 and not in 3.38 — no architectural blocker, no third-party breakage:

| API | Sites | Fix |
|---|---|---|
| `ScrollCacheExtent` / `scrollCacheExtent:` | `screens/addons/addon_hub_screen.dart` (1479, 1781, 1829), `widgets/detail/detail_layout_showcase.dart` (1112) | **Not droppable** — the call sites' own comment says "DPAD can only move to rows that are BUILT — pre-build far past the viewport so focus never hits an unbuilt-row wall." It is load-bearing for remote navigation, on exactly the platform we are targeting. Use 3.38's `cacheExtent: 2000` (confirmed present in `ListView`). |
| `ReorderableListView`'s `onReorderItem:` (3.38 has `onReorder:`) | `screens/settings/home_sections_filter_page.dart` (1023/1027), `screens/settings/quick_play_settings_page.dart` (565/570), `screens/settings/sidebar_customization_page.dart` (354/363), `screens/settings/widgets/manual_order_list.dart` (516/521) | **Not a plain rename — see the off-by-one trap below.** |
| `TickerMode.valuesOf` | `widgets/movie_watched_badge.dart` (56, 71) | Use `TickerMode.of(context)`, which returns the `bool` directly (confirmed present in 3.38). Drop the `.enabled`. |

#### The `onReorder` off-by-one trap

Do not mechanically rename `onReorderItem:` to `onReorder:`. They have **different index
semantics**, and Debrify's handler is written for the new one.

`ManualOrderList` forwards to `onMove`, typed `void Function(int from, int to)`, and every
implementation (e.g. `screens/settings/iptv_channel_order_page.dart:191`) does:

```dart
final item = _items.removeAt(from);
_items.insert(to, item);
```

That is **post-removal** indexing — what `onReorderItem` supplies. Classic `onReorder`
(`typedef ReorderCallback = void Function(int oldIndex, int newIndex)`, unchanged in 3.38)
reports `newIndex` computed *before* the item is removed, so dragging an item **downward** lands
it one position short. The shim must re-adjust:

```dart
onReorder: widget.enabled
    ? (oldIndex, newIndex) =>
        widget.onMove(oldIndex, newIndex > oldIndex ? newIndex - 1 : newIndex)
    : (_, __) {},
```

Only `manual_order_list.dart:521` constructs the `ReorderableListView`; the other three files are
its callers and should need no change once this one is fixed. `_move`'s existing
`to >= _items.length` guard stays correct — an end-of-list drop gives `newIndex == length`, which
the adjustment brings back into range.

**Preferred shape: target the 3.38 API surface, not a conditional.** Dart has no preprocessor, so
a version-conditional is awkward. All three older APIs (`cacheExtent`, `TickerMode.of`,
`onReorder`) are expected to still exist in 3.44 — write to those once and both toolchains
compile from a single code path. **Verify with `flutter analyze` on both 3.38.10 and 3.44.8
before merging**; that dual-version check is the acceptance test for this work.

**Ignore the package noise.** The run also reports 917 errors under `packages/`, but 834 are in
`packages/media_kit_patched/`'s **own test suite**, which has no `test` dev-dependency to resolve
(`Target of URI doesn't exist: 'package:test/test.dart'`, then every `test()`/`setUp()` undefined).
That is pre-existing, version-independent, and doubly irrelevant here — media_kit is cut on webOS
anyway (§4).

**Conclusion:** the skew costs roughly a day, not a re-architecture. It does not gate the port.
Prefer small compatibility shims over pinning the whole repo back to 3.38 — the other five
platforms should stay on 3.44.8.

---

## 7. Phased plan

### Phase 0 — Feasibility spike (no app code) · ~1–2 days
Gate the rest of the work on this.

1. Ubuntu 24.04 container/VM; install ares CLI (Node 16), webOS NDK, `flutter-webos`;
   `flutter-webos doctor -v` green on Flutter / webOS toolchain / Linux toolchain.
2. `flutter-webos create --platforms webos,linux hello` → build → `.ipk` → install on a real
   webOS 26 TV in Developer Mode. **If no TV is available, stop here** — everything downstream
   needs one.
3. On device, print `Platform.operatingSystem`, `Platform.version`, CPU arch, available memory.
4. Run the `video_player_webos` example. Answer the two scoping questions: **does it expose
   embedded audio/subtitle tracks in practice, and does a loopback proxy stream play?**
5. ~~Check out Debrify at Flutter 3.38.10; run `flutter analyze`.~~ **Done — see §6.** 18 errors
   in 6 files. Optionally confirm with a full `flutter build linux` on 3.38.10 once those are
   shimmed.

**Exit criteria:** hello-world `.ipk` runs on hardware, OS-identity answer known, player track
support answered. (3.38 skew: already quantified.)

### Phase 1 — Platform identity and compile-clean · ~3–5 days
1. `PlatformUtil.isWebOS` + `isTelevision` wiring; build-time define from the webOS build.
2. Audit all `Platform.isLinux` sites; split "desktop Linux" from "any Linux".
3. `flutter-webos create --platforms webos .` to generate `webos/` alongside `android/`,
   `linux/`, etc.; commit `webos/meta/flutter-conf.json` and `appinfo.json`
   (`"transparent": true`, app id, icons from `assets/`).
4. `pubspec.yaml`: add the `_webos` sibling implementations in a clearly commented block,
   mirroring the existing tvOS block.
5. Get it to **compile**, with everything unported behind `isWebOS` guards. Expect
   `MissingPluginException` at runtime — that is fine at this phase, and is the same trap the
   tvOS notes already describe.

### Phase 2 — Player abstraction · ~1.5–3 weeks
The bulk of the work. Extract the player interface, add the `video_player` backend, wire the
webOS build to it, handle the 5-pipeline budget, build the loopback header-injecting proxy for
IPTV, and degrade the tracks sheet honestly.

### Phase 3 — TV profile shakedown · ~1–2 weeks
Remote/D-pad key mapping (webOS Magic Remote, back key), focus traversal across the
`_BoardCell` grid, 10-foot layout checks, memory behaviour on a 32-bit ARM device, Skia vs
Impeller comparison, and hiding every cut feature (downloads, recording, file import,
brightness/volume gestures) from settings and navigation rather than leaving dead entries.

### Phase 4 — CI and release · ~2–4 days
Add a `webos` job to `.github/workflows/build.yml`, modelled on the existing `linux` job but on
`ubuntu-24.04`: cache the NDK and engine artifacts (`flutter-webos precache`), pin Node 16 for
ares, build `--release`, attach the `.ipk` to the GitHub release. Note the job cannot use the
repo-wide `flutter-version: '3.44.8'` pin — it uses the SDK's own toolchain.

Then: README/docs section on Developer Mode sideloading and session renewal, with the 50-hour
caveat stated honestly, alongside `docs/iOS-Installation.md`.

---

## 8. Open questions

1. ~~**Is the available TV running webOS 26?**~~ **Answered: no — it is on webOS 25.** This blocks
   Phase 0 outright: `flutter-webos` builds only for webOS 26+.
   **But the wait is likely short.** A webOS 25 set is a 2025 model, and 2025 models are the
   *first* cohort in the webOS 26 Re:New rollout, which began 22 Aug 2026 with the G5 OLED;
   C5/B5 and 2025 LCD models were slated to follow "within days and weeks" (2024/2023/2022 sets
   wait until late 2026 / early 2027). So the action is: **check Settings → Support → Software
   Update periodically**, and start Phase 0 the day webOS 26 lands. Do not rewrite the app for
   Route B to work around a wait measured in weeks.
2. Does `video_player_webos` expose embedded track selection in practice? Decides whether Phase 2
   is "adapt" or "lose a feature".
3. What does `Platform.operatingSystem` actually return?
4. ~~Does Debrify build against Flutter 3.38.10?~~ **Answered: yes, with 18 errors in 6 files.**
   See §6.
5. Is `pug_flutter` (analytics) portable, or stubbed on webOS?
6. Given Dev-Mode-only distribution, is the reachable audience worth the effort — or is this
   better parked until webosbrew regains webOS 26 support?

## 9. What would kill this

- No webOS **26** hardware. Currently the live blocker: the available TV is on webOS 25. An
  older webOS TV does not unblock this — the minimum is a hard SDK floor, not a soft one.
- ~~Debrify does not compile on Flutter 3.38.~~ Ruled out — see §6.
- `video_player_webos` has no track selection *and* no path to it — Debrify's playback identity
  is multi-track/multi-subtitle handling, and a player that cannot switch audio tracks is a
  different product.
- webosbrew stays broken on webOS 26 and Developer Mode friction keeps real-world installs near
  zero.
