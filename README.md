# AutoVid

<div align="center">
	<img src="https://i.imgur.com/kQfbveV.png" width="200" height="200" />
	<h1><strong>📹 AutoVid</strong> • Programmatically & Automatically Shoot App Videos •</h1>
	
</div>

**AutoVid** is a powerful macOS utility that bridges the gap between Xcode UI Tests and professional App Store previews. And you can show easily your app is working to your boss and CTO for proof. that you did not break sh\*t. But mainly creating for App Store previews because I hate creating App Store previews manually.

## Features

- **USB Capture Engine**: Records directly from your iPhone/iPad via USB (no AirPlay lag).
- **Xcode Integration**: Automatically scans your `Documents` and `Development` folders for `.xcodeproj` and `.xcworkspace` files.
- **Smart Automation**: Runs `xcodebuild test` commands for you, handling scheme and destination selection.
- **Live Logic**: Starts recording _exactly_ when the tests launch and stops when they finish.
- **Built-in Editor**:
  - Trim start/end points.
  - Crop/Scale for App Store (1290x2796), HD Portrait, or HD Landscape.
  - Validates 30-second App Store limit.
  - Exports high-bitrate MP4s.

## Prerequisites

- **macOS** (Sonoma or Sequoia recommended).
- **Xcode** installed with Command Line Tools.
- **iOS Device** connected via USB (Trust the computer).

## How It Works

1.  **Select Project**: Choose your iOS project from the dropdown.
2.  **Select Scheme**: Pick the scheme containing your UI Tests.
3.  **Target Device**: Select your connected iPhone (marked as "Real").
4.  **Run Automation**:
    - AutoVid triggers `xcodebuild test`.
    - It listens to the build logs.
    - When tests start, the "Recording" ruby light turns ON.
    - When tests finish, recording stops, and the Editor opens.

## The Editor

After a recording finishes, the **Editor Window** pops up:

- **Timeline**: Drag the left/right handles to trim the "setup" and "teardown" parts of your test.
- **Resolution**: Choose "App Store Preview" to auto-crop to the correct aspect ratio (fills screen, no black bars).
- **Export**: Saves the final `_EDITED.mp4` file to `~/Movies/AutoVid/`.

## 🤝 Companion SDK

For the best results, use this app with https://github.com/stevenselcuk/AutovidSDK. Also see mock app for example. https://github.com/stevenselcuk/AutoVidMockApp. The SDK allows your UI tests to "act human" (smooth scrolling, pauses, cinematic taps), which makes the recorded video look like a real production.

## Roadmap

- [ ] Xcode project discovery is hacky
- [ ] Avail. schema discovery is also hacky
- [ ] We are using timer and using native apis from 2008 that' does not give shit about Swift 6.
- [ ] Fully AppStore Preview support (no black bar, correct Frame/Bitrate, correct Resolution).
- [ ] Bring sandboxing to the app.
