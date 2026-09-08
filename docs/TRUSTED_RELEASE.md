# Trusted personal release checklist

Meno `0.1.x` is a macOS-only personal release. FileVault protects the live
database; a `.meno-backup` stored outside the app container provides independent
recovery. Automatic updates, public distribution, notarization, sync, and other
platform releases are intentionally deferred.

## One-time Sotto handoff

1. Launch the archived `Meno-Bridge` build. Its bundle identifier is
   `com.ivanchiew.sotto`, so it can reach the old sandbox.
2. Open Settings and choose **Import Sotto history**. Meno writes read-only
   copies of both source databases before merging anything.
3. Review the binder, then choose **Create backup** and save the resulting
   `.meno-backup` somewhere outside the app container.
4. Install the clean Meno build (`com.ivanchiew.meno`). On first launch, choose
   the bridge backup. Keep the Sotto container until at least two Meno backups
   have been successfully inspected or restored.

## Every update

1. From the installed Meno, create a fresh external backup.
2. Run `flutter analyze` and `flutter test`.
3. Run `flutter build macos --release` and launch the resulting app against a
   copied journal first.
4. Confirm entry editing, immediate quit-and-reopen, search, Settings backup,
   Markdown export, and restore into a disposable copy.
5. Replace the installed app manually. Never downgrade Meno over a database
   created by a newer build.

Local daily snapshots are secondary protection and are retained for 30 days.
Meno also retains the five newest pre-migration and pre-restore safety
snapshots. They do not replace an external backup or Time Machine.
