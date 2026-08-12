# Kaksha — Setup

A CSJMU smart-classroom app with three faces: **Student dashboard**, **Teacher dashboard**, and a **Smart Board** (works on People's Link interactive panels, Android, iOS, web, desktop).

## 1. Supabase (2 minutes)

1. Create a project at [supabase.com](https://supabase.com) (any name, e.g. `kaksha`).
2. Open **SQL Editor**, paste the whole contents of [`supabase/schema.sql`](supabase/schema.sql), press **Run**.
3. Go to **Project Settings → API** and copy two values:
   - **Project URL** (looks like `https://abcdefgh.supabase.co`)
   - **anon public key** (long string starting with `eyJ…`)
4. Paste them into [`lib/config.dart`](lib/config.dart).

That's it — no auth setup needed for the prototype (open RLS policies are created by the schema).

## 2. Run

```bash
flutter pub get
flutter run           # pick a device: Chrome, Android, iOS, macOS…
```

### AI slide translate/describe (optional)

The student "Translate slide" / "Describe slide" buttons use Google Gemini.
Get a key at [aistudio.google.com/apikey](https://aistudio.google.com/apikey) and pass it at build time
(don't commit it — GitHub will block the push):

```bash
flutter run --dart-define=GEMINI_API_KEY=your-key-here
```

For the smart board (People's Link panels run Android/Windows):

- **Android panel**: `flutter build apk --release` → install `build/app/outputs/flutter-apk/app-release.apk`
- **Any panel with a browser**: `flutter build web` and host, or `flutter run -d chrome`

## 3. Demo flow

1. **Student** → register (e.g. *Maheshwar*, roll no, *B.Tech CSE*, *1st Year*) → auto-enrolled in a classroom, gets a classroom code like `CSE1-7KQ2`.
2. **Teacher** → register (name + employee ID) → add weekly slots (e.g. Mon/Tue/Fri, B.Tech CSE 1st year, 2–3 PM) → the same classroom is linked automatically.
3. Student's calendar now shows those classes on the right days, with the teacher's name.
4. **Smart Board** → enter the classroom code → full whiteboard with slides; drawings save to the classroom.
