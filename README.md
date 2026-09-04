# Meno

Meno is a private, local-first journal for desktop and mobile. It combines a
quiet full-page editor with a horizontal daily binder, optional on-device smart
organization, and an optional Scripture workspace for Quiet Time journaling.

Journal writing, gratitude, mood, tags, relationships, Scripture attachments,
and preferences are stored on the device. The core journal does not require an
account, network connection, or AI model.

## The journal experience

- One pinned **Daily Journal** for each recorded date, with a gratitude footer.
- Any number of separate **Additional Entries** in the same day.
- A shared daily mood check-in represented as reflective tone and intensity,
  not a diagnosis.
- Time-aware routing: before the configured evening time Meno opens an
  unfinished Daily Journal; in the evening it asks for a missing mood first.
- A fast horizontal binder for browsing recorded days, weeks, and months.
- A compact, always-visible entry wheel for moving between a day's entries.
- Historical writing, gratitude, and mood remain editable.

Daily completion only requires a non-empty Daily Journal and a mood check-in.
Gratitude and Additional Entries are always optional.

## Smart Organization

Smart Organization is optional and runs locally:

- RAKE-based keyphrase extraction generates editable tags without downloading
  a model.
- Full-text search filters by text, tag, purpose, Scripture book, and date.
- A ranked Related Entries view is the primary cross-reference experience.
- A bounded Connections graph shows at most 40 entries and the three strongest
  relationships per entry.
- An optional quantized
  [Snowflake Arctic Embed XS](https://huggingface.co/Snowflake/snowflake-arctic-embed-xs)
  ONNX model improves semantic matching. It is English-first, downloads on
  demand from Settings, and is verified before use.

If the embedding model is absent or unavailable, tag extraction, full-text
search, and shared-tag relationships continue to work. Generated tags never
replace manual tags.

## Quiet Time logging

Quiet Time logging is optional and hidden when disabled. It adds:

- A focused choice of ESV, NIV, ERV, and NKJV through YouVersion.
- A continuous Scripture reader shown in a sliding split view on desktop and
  as a draggable, near-full-height sheet on phones.
- Single-verse and contiguous-range selection with linked, borderless verse
  blocks below the journal text.
- Quiet Time entries with optional Observation, Application, and Prayer fields.
- Translation access when the app has an approved registration, the requested
  version is licensed, and the device is online.

Only user-authored reflection and structured Scripture references are embedded.
Licensed passage text is resolved on demand and is not stored in journal
records.

### Optional YouVersion setup

Register the app and follow the current
[YouVersion Platform API requirements](https://developers.youversion.com/api-usage).
Supply the key at build or run time; never commit it:

```sh
flutter run -d macos --dart-define=YOUVERSION_APP_KEY=your_app_key
```

Without a key or the necessary translation licenses, the Scripture workspace
explains that access is unavailable. Passages retain their required translation
label and copyright attribution.

## Getting started

Install Flutter and the platform toolchain for the device you want to run, then:

```sh
flutter pub get
flutter run -d macos
```

Use `flutter devices` to find an attached phone, simulator, or other available
desktop target and pass its identifier to `flutter run -d`.

## Architecture

- `lib/models` — journal, discovery, embedding, and Scripture data types.
- `lib/services/database_schema.dart` — the current SQLite schema.
- `lib/services/database_service.dart` — runtime persistence, FTS5,
  pagination, transactions, and local search.
- `lib/services/keyphrase_service.dart` — RAKE extraction and journal-specific
  phrase filtering.
- `lib/services/embedding_service.dart` — model lifecycle, checksum validation,
  tokenization, and ONNX inference.
- `lib/services/organization_service.dart` — tagging, canonicalization, gradual
  indexing, and related-entry ranking.
- `lib/services/bible_service.dart` — licensed YouVersion Bible access.
- `lib/providers` — time-aware routing, editor state, binder navigation, and
  capability-aware optional services.
- `lib/ui` — mood dial, full-page editor, binder, discovery, settings, and
  Scripture workspace.

The unreleased app uses a clean schema version 1. A higher-version development
database is deleted and recreated rather than migrated. Drafts autosave after
700 ms of inactivity. Optional back-catalog indexing is cancellable and never
blocks journal editing.

## Verification

```sh
flutter analyze
flutter test
flutter build macos --debug
flutter test integration_test/embedding_smoke_test.dart -d macos
```

The embedding smoke test downloads the model into a temporary directory,
validates its checksum, runs native ONNX inference, and removes the temporary
copy afterward.

Current verification status:

| Target | Status |
| --- | --- |
| macOS 14+ | Analyzer, full tests, debug build, and native embedding smoke test verified |
| iOS 16+ | Source configured; requires an Apple mobile build environment and signing |
| Android | Source configured; build verification requires an installed Android SDK |
| Windows | Flutter project target is present; release validation requires a Windows host |
| Linux | Not currently generated in this repository |

## Privacy and network behavior

- Journal data and analysis stay on-device.
- Smart Organization only uses the network to download its optional model.
- Quiet Time logging uses the network for explicitly selected YouVersion content.
- No API keys are stored in the repository.

## License

Meno is available under the [MIT License](LICENSE). Models, packages, and
remote Bible translations retain their respective licenses and attribution
requirements. Arctic Embed XS is Apache-2.0 licensed; YouVersion content is
governed by the terms and translation licenses granted to the registered app.
