# Majalis Manager — Requirements

An offline-first Android app for a single Shia scholar to schedule and manage their **Majalis**, **Milads** and **Nikkahs**.

This document is the end-goal verification checklist: the app's fundamental functionality is complete when every `[ ]` below can be ticked on a real phone.

Items marked *(default)* were not explicitly decided and use a sensible default. Change them here if needed.

---

## 1. Scope

### In scope
- One user (the scholar), on one or more phones. One optional sign-in, used only for cloud sync.
- Offline-first. Every feature works without internet; when online, phones that are signed in sync through Supabase.
- Event types: **Majlis**, **Milad**, **Nikkah**.
- Booking/schedule management, host directory, reminders, sharing, backup.
- English and Urdu UI.

### Out of scope
- Speech/content preparation (ayat, ahadith, masaib, poetry).
- Hadiya / payment / travel tracking.
- Haq Mehr, Nikkah certificate, sigha text, and Nikkah party details (groom, bride, fathers, wakeels, witnesses).
- Multiple users or roles, web version, iOS.

---

## 2. Navigation

Bottom navigation with three tabs, and a **gear icon** in the top bar that opens Settings.

| Tab | Purpose |
|---|---|
| **Home** | Today plus the upcoming events in a chronological list |
| **Create** | Google Keep-style card grid to create and edit events |
| **Calendar** | Visual calendar (top) plus a list for the displayed month (bottom) |

- [ ] N1. The app opens on **Home**.
- [ ] N2. All three tabs are reachable from the bottom bar, and the gear icon opens Settings from any tab.
- [ ] N3. In Urdu mode the bottom bar order and the top bar mirror (RTL).

---

## 3. Events (common to all types)

### 3.1 Fields
| Field | Required | Notes |
|---|---|---|
| Type | Yes | Majlis / Milad / Nikkah |
| Hijri date | Yes | Picked first (see §4) |
| Gregorian date | Auto | Calculated from Hijri; can be overridden per event |
| Start time | Yes | |
| End time | Yes | Pre-filled from the type's default duration; editable |
| Venue / address | Yes | Pre-filled from the host's saved venue; editable per event |
| Host | No | Existing or new host (see §6); can be removed from an event |
| Topic / occasion | No | e.g. "Shahadat Imam Hussain (a.s.)", "Muharram 7th" |
| Status | Yes | Tentative / Confirmed / Cancelled / Done |

- [ ] E1. An event of each type can be created with the fields above and saved.
- [ ] E2. The end time pre-fills as start time + the default duration for that type, and the user can change it before saving.
- [ ] E3. Default durations per type are editable in Settings. *(default: Majlis 1h30, Milad 1h30, Nikkah 1h)*
- [ ] E4. Any saved event can be opened, edited and re-saved.
- [ ] E5. An event can be deleted after a confirmation prompt.
- [ ] E6. Data entry fields accept Urdu as well as English text.

### 3.2 Status
- [ ] E7. A new event defaults to **Confirmed**. *(default)*
- [ ] E8. Status can be changed manually to any of Tentative / Confirmed / Cancelled / Done.
- [ ] E9. Auto-Done is driven by the **Islamic date**. The app tracks today's Hijri date (with the global moon-sighting offset applied). Once an event's Hijri date is before today's Hijri date, any **Tentative** or **Confirmed** event is marked **Done** automatically and treated as a past event. Cancelled events stay Cancelled.
- [ ] E9a. The auto-Done check runs on app launch and whenever the Hijri date rolls over while the app is open. Changing the moon offset re-evaluates it.
- [ ] E10. **Cancelled** events stay visible (greyed or struck through) for history, but are excluded from clash checks and reminders.

### 3.3 Nikkah
- [ ] E11. A Nikkah has the same fields as a Majlis or Milad (§3.1). There are no groom, bride, wakeel or witness fields.

### 3.3a Flier (Majlis and Milad only)
- [ ] E12. A Majlis or Milad can have **one optional flier** (an image). Nikkah events never show flier options.
- [ ] E13. The flier is hidden until the event is opened. Directly under the title, above everything else, a button reads **Add flier** (none yet) or **View flier** (one attached).
- [ ] E14. **Add flier** opens the phone's photo gallery. The image is shrunk to about 1600 px (a few hundred KB) before it is stored.
- [ ] E15. **View flier** opens it full screen with pinch-to-zoom and four actions: **Share** (the flier only), **Replace**, **Save to gallery**, **Remove** (after a confirmation).
- [ ] E16. Mimbar appears in other apps' **Share** menu for images. Sharing a flier from WhatsApp to Mimbar lists the upcoming (then recent past) Majlis and Milad events, and tapping one attaches it, asking first if it would replace an existing flier.
- [ ] E17. Event cards in lists show a small image icon when the event has a flier.
- [ ] E18. With cloud sync on, fliers sync to the other phone (Supabase Storage, private to the account). Unused fliers are deleted from the cloud.

### 3.4 Majlis series (Individual / 3 / Khamsa / Ashra)
- [ ] E13. For **Majlis only**, the form has a **Series** dropdown: Individual *(default)*, 3 days, Khamsa (5), Ashra (10).
- [ ] E14. Choosing 3/5/10 and saving creates that many linked Majlis events on consecutive Hijri days, starting on the chosen date, each with the same host, venue, time and topic.
- [ ] E15. Each event in a series can be edited, cancelled or deleted individually without affecting the others.
- [ ] E16. Events in a series show their position, e.g. "Ashra — Day 3/10".
- [ ] E17. The Series dropdown does not appear for Milad or Nikkah.

---

## 4. Hijri-first dates

The Hijri date is the source of truth. The Gregorian date is derived from it.

- [ ] D1. The date picker opens in **Hijri** (day / Hijri month / Hijri year), and the matching Gregorian date is shown live beside it.
- [ ] D2. Settings has a **global moon-sighting offset** from −2 to +2 days *(default 0)*. Changing it shifts the Gregorian date of every event that has no override, and reschedules their reminders.
- [ ] D3. Each event can **override** its Gregorian date manually. An overridden event ignores the global offset and shows a small "adjusted" indicator.
- [ ] D4. Everywhere a date is shown (cards, lists, share text), both the Hijri and Gregorian dates are shown, e.g. "7 Muharram 1448 · 23 Jun 2026".
- [ ] D5. Hijri month names appear in the current UI language (e.g. Muharram / محرم).
- [ ] D6. Conversion uses the Umm al-Qura calendar and is correct for at least 1440–1470 AH.

---

## 5. Clash detection

Two non-cancelled events **clash** if their time ranges overlap on the same Gregorian date. Overlap means `startA < endB && startB < endA`, which also covers identical start times.

- [ ] C1. When saving a new or edited event that clashes with another, a **warning** appears before saving and lists the clashing event(s).
- [ ] C2. The warning offers **Save anyway** (override) and **Go back**.
- [ ] C3. After an override, both events are flagged as clashing and shown as "Event 1 + Event 2 (Clashing)" in the Calendar list and the Create grid.
- [ ] C4. Clashing events use the **yellow** clash colour indicator (see §7).
- [ ] C5. If a clash is resolved (one event is moved, cancelled or deleted), the clash flag disappears from both automatically.
- [ ] C6. Creating a Majlis series checks each generated day for clashes and lists all of them in one warning.

---

## 6. Host directory

- [ ] H1. Every host has a **name**, a **phone number** and an optional saved **default location**. The phone number is the unique key.
- [ ] H1a. Selecting a host pre-fills the event's venue with the host's saved venue.
- [ ] H1b. The venue can be edited for that one event without changing the host's saved venue. The saved venue changes only when the host itself is edited.
- [ ] H2. A host is **optional**. When creating or editing an event, the user can leave it empty, choose **Select existing host** (searchable by name or phone) or **Create new host**, or remove the selected host.
- [ ] H3. Creating a host with a phone number that already exists is blocked, and the app offers the existing host instead.
- [ ] H4. Phone numbers are normalised before comparison (spaces and dashes ignored; `03xx…` and `+923xx…` treated as the same). *(default)*
- [ ] H5. Editing a host's name updates it on all of that host's events.
- [ ] H6. A host's detail view lists all of their past and upcoming events.
- [ ] H7. The New host dialog starts with **Import from contacts**, which opens the phone's contact picker. Picking a contact fills in its name and number (the contact's default number, else the most recently added). Other numbers show as chips to switch between. Both fields stay editable, and typing a host in by hand still works.
- [ ] H8. Importing needs the Contacts permission, asked the first time. If it is refused, the dialog says how to allow it. Mimbar reads only the picked contact.

---

## 7. Screens

### 7.1 Home
- [ ] S1. The header shows today's Hijri and Gregorian dates.
- [ ] S2. It shows **today's** events first, then **upcoming** events in chronological order.
- [ ] S3. Tapping an event opens it for viewing or editing.

### 7.2 Create (Keep-style grid)
- [ ] S4. Events appear as cards in a Google Keep-style grid.
- [ ] S5. On open, the grid is positioned at **today**. Upcoming events follow below, and **scrolling up reveals past events**.
- [ ] S6. A **+ New** button opens the event form. Tapping a card opens that event for editing.
- [ ] S7. Each card shows its type, Hijri and Gregorian date, time, host, venue, topic and status.
- [ ] S8. Each card has a **thick colour line on its top or bottom edge only** (the card itself is not filled):
  - Majlis — **black**
  - Milad — **red**
  - Nikkah — **green**
  - Clashing — **yellow**
- [ ] S9. A **search bar** filters cards by host name, phone, venue or topic.
- [ ] S10. **Filter chips** filter by type (Majlis / Milad / Nikkah) and by status.

### 7.3 Calendar
- [ ] S11. A pinned month header (‹ month ›, calendar on/off, Hijri/Gregorian) sits above a compact month grid (about a third of the screen) and the list of that month's events. The grid scrolls away with the list; the header stays.
- [ ] S11a. The calendar on/off button hides the grid, leaving only the chronological list for the same month. Each phone remembers its choice.
- [ ] S12. A toggle switches the month view between **Hijri month** and **Gregorian month**, and the list follows the same range.
- [ ] S13. Day markers (Majlis black, Milad red, Nikkah green), at the bottom of the day box:
  - one type of event → a wide bar in its colour, with the count in the middle when there is more than one;
  - several types → one dot per type, in the order Majlis, Milad, Nikkah, each with its count when above one (e.g. 1 Nikkah + 3 Milad → a red dot with 3 and a plain green dot);
  - a clash on that day → a small yellow warning in the day's corner;
  - cancelled events are not counted; past days' markers are faded.
- [ ] S14. Swiping or using arrows changes the month. Tapping a day scrolls or filters the list to that day.
- [ ] S15. Clashing events appear in the list as "Event 1 + Event 2 (Clashing)".

---

## 8. Language (English / Urdu)

- [ ] L1. Settings has a **Language** toggle: English / اردو.
- [ ] L2. Urdu mode translates **all** UI text, uses a **Nastaliq** font and switches the whole layout to **RTL**.
- [ ] L3. The switch applies immediately without reinstalling. An in-app restart is acceptable.
- [ ] L4. The choice persists across app restarts.
- [ ] L5. Share text (§10) is produced in the current UI language.

---

## 9. Reminders (offline local notifications)

- [ ] R1. Every non-cancelled upcoming event schedules local notifications at the lead times set in Settings. *(default: 1 day before and 2 hours before)*
- [ ] R2. Notifications fire while the app is closed, with no internet.
- [ ] R3. Reminders are rescheduled when an event is edited, the moon offset changes or the phone restarts.
- [ ] R4. Cancelling or deleting an event removes its reminders.
- [ ] R5. Tapping a notification opens that event.

---

## 10. Sharing

- [ ] SH1. Each event's **Share** button opens a sheet: first **Text / Flier / Both** (the flier choices only when the event has one), then **Facebook**, **WhatsApp** or **More…** (the Android share sheet).
- [ ] SH2. The shared text is formatted and includes the type, topic, Hijri and Gregorian date, start–end time, venue and host (when set).
- [ ] SH3. Facebook opens straight in its post composer with the flier. Facebook doesn't accept text from other apps, so the text is copied and a note says to paste it as the caption.
- [ ] SH4. If Facebook or WhatsApp isn't installed, the app says so and falls back to the Android share sheet.

---

## 11. Backup (manual export / import)

- [ ] B1. Settings has **Export backup**, which writes all events, hosts and settings to a single file (`.json`) that can be saved or shared (WhatsApp, USB, Drive, etc.).
- [ ] B2. **Import backup** reads that file. After a confirmation prompt it **replaces** all current data. *(default)*
- [ ] B3. A backup exported on one phone and imported on another restores everything exactly: events, series links, hosts, overrides, statuses and settings.
- [ ] B4. Importing an invalid or corrupt file fails safely with a message and leaves existing data untouched.
- [ ] B5. When signed in to sync, an import also replaces the data on the other phones (rows missing from the backup are deleted there too).

---

## 12. Cloud sync (Supabase, optional)

- [ ] CS1. Settings → **Cloud sync** signs in with an email and password (one account, created in the Supabase dashboard). Signing in is optional; without it the app behaves exactly as before.
- [ ] CS2. The app always reads and writes the on-phone database. With no internet, every change is kept and uploaded automatically once a connection returns.
- [ ] CS3. A change saved on one phone appears on the other within a few seconds when both are online (live updates), or the next time the other phone opens the app.
- [ ] CS4. Events, hosts, deletions and settings (language, moon offset, durations, reminders) all sync.
- [ ] CS5. If the same event is edited on both phones while offline, the later edit wins on both phones.
- [ ] CS6. If both phones save the same phone number as a new host while offline, they merge into one host and the events of both point to it.
- [ ] CS7. On first sign-in, existing data on the phone is merged with the cloud (nothing is lost). A freshly installed phone's default settings never overwrite the other phone's.
- [ ] CS8. Settings shows the signed-in email, the last sync time, a **Sync now** button and **Sign out**. Signing out keeps the data on the phone.
- [ ] CS9. Each phone schedules its own reminders from the synced events. *(Limitation: a booking added on phone A reaches phone B's reminders only once B has opened the app and synced.)*
- [ ] CS10. Only the signed-in account can read or write its data (row-level security); new sign-ups are disabled in Supabase.

---

## 13. Settings (gear icon)

- [ ] ST1. Language: English / Urdu
- [ ] ST2. Moon-sighting offset: −2 … +2
- [ ] ST3. Default duration per type: Majlis, Milad, Nikkah
- [ ] ST4. Reminder lead times
- [ ] ST5. Cloud sync: sign in / status / sync now / sign out
- [ ] ST6. Export / Import backup

---

## 14. Non-functional

- [ ] NF1. Works with airplane mode on, for every feature (sync waits for a connection).
- [ ] NF2. Data survives app restarts and phone reboots (on-device SQLite).
- [ ] NF3. The app opens to Home in under 2 seconds on a mid-range phone.
- [ ] NF4. The grid and lists stay smooth with 2,000+ events (several years of bookings).
- [ ] NF5. Runs on Android 8.0+ (API 26+).
- [ ] NF6. The screens use a white background. Time pickers always show the 12-hour dial with AM/PM, even when the phone is set to 24-hour time.

---

## 15. Tech stack

**Flutter (Dart) + SQLite**, built into an APK locally on Windows.

| Concern | Choice |
|---|---|
| Framework | Flutter 3.47 (stable) |
| Database | SQLite via `sqflite` (no code generation) |
| Hijri ↔ Gregorian | `hijri` package (Umm al-Qura), plus the offset/override logic |
| Calendar widget | Custom month grid (shared by the Calendar tab and the Hijri date picker) |
| Keep-style grid | `flutter_staggered_grid_view` |
| Notifications | `flutter_local_notifications` + `timezone` + `flutter_timezone` (exact alarms, reschedule on boot) |
| Localisation / RTL | `flutter_localizations` + in-app English/Urdu string tables; Noto Nastaliq Urdu font bundled |
| State management | One `ChangeNotifier` store (`lib/data/store.dart`) |
| Share | `share_plus` |
| Backup file | `file_picker` (save/open) + `share_plus` (send) |
| Cloud sync | `supabase_flutter` (Postgres + auth + realtime) + `connectivity_plus`; schema in `supabase/schema.sql`. Last-write-wins per row by edit time, deletes kept as tombstones. |

**Android permissions:** `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM` / `USE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`, `INTERNET` / `ACCESS_NETWORK_STATE` for cloud sync, `READ_CONTACTS` for importing hosts, and `WRITE_EXTERNAL_STORAGE` (Android 9 and older only) for saving fliers to the gallery.

**Distribution:** built locally with `build.ps1`, then published as a GitHub Release. Download the APK on the phone from the repo's Releases page (or copy it over USB/WhatsApp), allow "Install unknown apps" once, then install. No Play Store.

### Why Flutter (decision record)
- **Chosen over Kotlin/Compose:** comparable reliability for this scope, much faster UI iteration, and ready-made calendar and grid widgets.
- **Chosen over Expo/React Native:** a runtime English↔Urdu RTL toggle is clean in Flutter but awkward in React Native (`forceRTL` requires a restart and has Nastaliq rendering bugs), and React Native APK builds need either EAS cloud or the full Android SDK anyway.
- **Chosen over a PWA:** a PWA can't fire reliable background reminders offline, so an APK was accepted.

---

## 16. Open questions
None at present.
