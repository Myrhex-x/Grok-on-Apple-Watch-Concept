# Grok for Apple Watch

A personal Apple Watch app (watch only, no iPhone app) that talks to Grok with your own SpaceXAI API key. Ask by voice or with the keyboard; the answer comes back as text, never spoken. Grok answers in English unless you ask in another language. Built for personal use.

## Using it

- **Open the app and speak.** For a new question, dictation starts on its own as the app opens (Settings, "Dictate on open" turns that off). Otherwise the white microphone goes straight into dictation in one tap.
- **Or type**: the keyboard button opens the watch keyboard (or Scribble). When the watch asks for text, the iPhone also offers to type it.
- **The answer streams in** under your question. "Thinking" or "Searching the web" shows while Grok works; the square button stops it. The watch taps once when the answer is done.
- **Lower your wrist** while it answers and nothing is lost: the answer finishes in the background and arrives as a notification.
- **Follow-up questions** keep the context. "+" starts a new conversation; after an hour away, opening the app starts one by itself, with the last conversation one tap away ("Previous conversation").
- **Settings**: the model (from the list your key can use, cheapest first, grok-4.3 by default), how long Grok thinks (None, Short, Deep), web search (on, about 0.005 USD a search, only when the question needs it), X search (off by default, about 0.10 USD a search), what this watch spent this month, and the date the install ends.

## Setting up

1. Install it (below).
2. Give it your key from the Mac: copy the key (console.x.ai or your password manager), then run

   ```bash
   ./install-key.sh
   ```

   It reads the key from the clipboard without showing it, checks it with SpaceXAI (listing models is free), copies it into Grok's own folder on the watch and opens Grok, which moves it into the watch's Keychain and deletes the file. Nothing stays on the Mac. (Typing it on the watch also works: "Add key", then the iPhone's offer to type for the watch.)
3. Allow notifications when the watch asks: they carry answers that land with your wrist down, and the reminder before the install ends.

The key lives only in the watch's Keychain (this device only, not backed up) and is only ever sent to `api.x.ai`. Requests go with `store: false`, so the conversation is not kept on SpaceXAI's side. To change the key later, copy the new one and run `./install-key.sh` again.

## Installing, and installing again

The app is installed from this Mac, not the App Store, so it runs until its provisioning profile or the development certificate that signed it ends, whichever comes first. With the paid developer account that is up to a year; right now the development certificate ends on **July 14, 2027**, so that is the date. The watch shows it in Settings, warns in the app two weeks before, and sends reminders a week before, two days before and the evening before.

To install (or reinstall to extend it): unlock the iPhone and connect it to this Mac, keep the watch on your wrist and unlocked, then run

```bash
./install-on-watch.sh
```

The first time:

1. The iPhone must be paired with this Mac and in Developer Mode. A phone Xcode has never seen does not show up at all: `xcrun devicectl manage pair --device <its UDID>` makes it ask to trust the Mac, then turn on Settings > Privacy & Security > Developer Mode on the iPhone.
2. watchOS 27 does not pair with the Mac through the iPhone. Open Device Hub (Xcode 27's device manager), choose File > Pair Nearby Device…, and leave it waiting. Put the watch on the same Wi-Fi as the Mac (turning Bluetooth off on the iPhone, in Settings, makes it switch), then on the watch open Settings > Privacy & Security > Developer Mode, turn it on and pair with the Mac. Turn Bluetooth back on afterwards.
3. The script registers the watch with the developer account on its first run.

If the script cannot install, open `GrokWatch.xcodeproj` in Xcode, pick the watch as the destination and press Cmd-R. Reinstalling keeps your key and settings.

## Building and testing

```bash
xcodebuild -project GrokWatch.xcodeproj -scheme GrokWatch -configuration Debug -destination 'platform=watchOS Simulator,name=Grok Watch' -derivedDataPath build/dd build
```

```bash
Tests/run.sh
```

`Tests/run.sh` runs the logic tests on the Mac (stream parsing, API errors, model choice, answer text, conversation, install dates and reminders, spending, prompt) and fails if an em or en dash slipped into the sources. The Team ID lives in `Config/Local.xcconfig`, not in the project. The icon is drawn by `Tools/make-icon.swift`.

Debug builds take launch arguments for the simulator: `-GrokWatchSimulated YES` (a pretend Grok, nothing sent or billed), `-GrokWatchKey <key>` (a key for that run only), `-GrokWatchAsk "<question>"`, `-GrokWatchDemo YES`, `-GrokWatchFakeExpiryDays 5`, `-GrokWatchPage settings|settings-bottom|key`, `-GrokWatchNoAutoDictation YES`.

## How it works

- `Grok/GrokClient.swift`: the SpaceXAI Responses API (`POST https://api.x.ai/v1/responses`), streamed. Web and X search are SpaceXAI's server-side tools, capped at 3 turns. If the chosen model is retired, the app switches to grok-4.3 (or the cheapest text model listed) and asks again.
- `Chat/ChatModel.swift`: the conversation, the background time (`performExpiringActivity`), the tap or the notification when an answer lands.
- `System/Dictation.swift`: one tap into dictation with WatchKit's text input controller (no suggestions, plain text).
- `System/ProvisioningProfile.swift` and `InstallExpiry.swift`: the end date from the embedded profile and its certificates, and the reminders.
