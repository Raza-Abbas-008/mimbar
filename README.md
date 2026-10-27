# Mimbar

An offline-first Android app for a Shia scholar to schedule and manage **Majalis**, **Milads** and **Nikkahs**: Hijri-first dates, clash warnings, a host directory, reminders, English/Urdu, backup, and optional cloud sync between phones.

The full feature checklist is in [REQUIREMENTS.md](REQUIREMENTS.md).

## Install on a phone

1. On the phone, open this repo's **Releases** page and download the latest `Mimbar.apk`.
2. Open it. Allow **Install unknown apps** for your browser when Android asks (once only).
3. If Play Protect warns, tap **More details → Install anyway**.
4. Open Mimbar and allow notifications.

Updating works the same way. Install the new APK over the old one and the data is kept.

## Cloud sync setup (once)

Sync is optional. Without it, the app works fully offline on one phone.

1. Create a project at [supabase.com](https://supabase.com) (the free tier is plenty).
2. **SQL Editor** → paste [supabase/schema.sql](supabase/schema.sql) → **Run**.
3. **Authentication → Users → Add user**: create one user with an email and password, and tick *Auto confirm*.
4. **Authentication → Sign In / Providers**: turn **off** *Allow new users to sign up*, so nobody else can create an account.
5. **Project Settings → API Keys**: copy the project URL and the **publishable** key (`sb_publishable_…`, or the legacy `anon` key). Never use the `service_role` / secret key.
6. Copy `mimbar/supabase.example.json` to `mimbar/supabase.json` and fill in both values. This file is git-ignored.
7. Build (below). On each phone: **Settings → Cloud sync → Sign in** with the user from step 3.

## Build

Needs Flutter, JDK 17 and the Android SDK (installed under `C:\dev` on the build PC).

```powershell
.\build.ps1            # writes .\Mimbar.apk
```

The release signing key lives in `keys/` and is never committed. Back that folder up: without it, future APKs can't install over the existing app.

## Publish a release

```powershell
gh release create v1.1.0 Mimbar.apk --title "Mimbar 1.1.0" --notes "What changed"
```

Bump `version:` in `mimbar/pubspec.yaml` before each release.

## Project layout

| Path | What |
|---|---|
| `mimbar/lib/data/` | SQLite schema (`db.dart`), models, and the app store |
| `mimbar/lib/services/sync.dart` | Supabase sync: upload dirty rows, download newer ones, live updates |
| `mimbar/lib/ui/` | Screens and widgets |
| `mimbar/test/` | Unit tests, including two-phone sync scenarios against a fake cloud |
| `mimbar/tool/make_icon.py` | Generates the 3D minbar app icon |
| `supabase/schema.sql` | Cloud tables, last-write-wins trigger and row-level security |
