# MagicMagicTrack Installation Guide

How to install MagicMagicTrack and open it for the first time.

The app is currently distributed without Apple Developer ID signing and notarization, so macOS shows a security warning the first time you open it. Allow it once as described in section 3 and the app opens normally after that.

## 1. Download

Download one of these files from [Releases](https://github.com/taehee33/magictrack202603/releases/latest).

- Recommended: `MagicMagicTrack-<version>.dmg`
- Alternative: `MagicMagicTrack-<version>-macOS.zip`
- `SHA256.txt`: to check that the downloaded file was not altered (optional)

```bash
shasum -a 256 ~/Downloads/MagicMagicTrack-*.dmg
```

If the output matches the value in `SHA256.txt`, the file is intact.

## 2. Install

### DMG

1. Double-click the `.dmg` file.
2. Drag `MagicMagicTrack.app` into the `Applications` folder.

### ZIP

1. Double-click the `.zip` file to extract it.
2. Move `MagicMagicTrack.app` into the `Applications` folder.

Always run the app from the `Applications` folder. Running it straight from Downloads can keep permissions from sticking.

If you have the old `MagicTrack.app`, delete it. Settings, presets, and app rules carry over.

## 3. First launch ("unidentified developer" warning)

1. Double-click `MagicMagicTrack.app` in the `Applications` folder.
2. When a warning such as "Apple could not verify 'MagicMagicTrack' is free of malware" appears, click **Done** (or Cancel).
3. Open **System Settings › Privacy & Security** and scroll down.
4. Next to "'MagicMagicTrack' was blocked", click **Open Anyway**.
5. Confirm with your password or Touch ID, then click **Open Anyway** again.

After you allow it once, the app opens normally.

> Since macOS 15, right-click › Open no longer bypasses this warning. Use **Open Anyway** in System Settings.

### If you see "is damaged and can't be opened"

This can be caused by the quarantine flag attached to downloaded files. After moving the app to `Applications`, run this in Terminal and open the app again.

```bash
xattr -dr com.apple.quarantine /Applications/MagicMagicTrack.app
```

## 4. Permissions

| Feature | Permission |
|---|---|
| Speed, scrolling, click pressure, automatic switching, app rules, 180° rotation | None |
| Magic Trackpad Left / Right 90° rotation | Accessibility |

If you turn on 90° rotation without the permission, the Magic Trackpad card shows a notice.

1. Click **Open Permissions** on the card (or go to **System Settings › Privacy & Security › Accessibility**).
2. Turn on `MagicMagicTrack` in the list.

Rotation starts right away; no relaunch needed. If `MagicMagicTrack` appears more than once in the list, you can remove the old entries.

## 5. Basic use

### Trackpad tab

- Cards for the built-in trackpad and the Magic Trackpad appear side by side.
- Set tracking speed, scrolling speed, and click pressure per card. Changes apply immediately.
- **Switch mode**: Auto (uses the settings of the trackpad you touch) / Built-in Only / Magic Only
- Choose the rotation (None · 180° · Left 90° · Right 90°) on the Magic Trackpad card.
- Each setting can be reset to "My Default" or "Mac Default".

### Presets tab

- Save the current settings as a preset; edit, duplicate, or delete presets.
- **App rules**: apply a preset automatically when you use a specific app.

### Settings tab

- Launch at login, Dock and menu bar icons, showing the trackpad in use and its rotation in the menu bar
- Language (한국어 / English)
- Switch mode shortcut (`⌃⌥M` by default; can be changed or turned off)
- Check for new versions

### Menu bar

Next to the menu bar icon, the trackpad in use and its rotation are shown as `Built-in`, `Magic L 90°`, and so on. Click it to change the switch mode or preset.

**System Settings values are never changed.** The app only overrides the running values while it is open; quitting restores the System Settings values.

## 6. Known limitations

- The app uses private macOS features. A macOS update may break some features. If automatic switching is unavailable, the app falls back to a fixed mode.
- At 90°, two-finger page swipes (back / forward) are not rotated.
- It installs on macOS 14 or later, but has only been tested on macOS 27.

## 7. Troubleshooting checklist

1. Did you run the app from the `Applications` folder?
2. Did you click **Privacy & Security › Open Anyway**?
3. If you see "is damaged and can't be opened", did you run the `xattr` command in section 3?
4. If 90° rotation does not work, is `MagicMagicTrack` turned on under **Accessibility**?
5. If it still does not work, quit from the menu bar icon and open the app again.

When reporting a problem, turn on Settings tab › Advanced › **Developer Mode** to show the device and switching log below the Trackpad tab. Take a screenshot and post it to [Issues](https://github.com/taehee33/magictrack202603/issues).

## 8. FAQ

### Why is there a warning the first time?

The app is distributed without Apple Developer ID signing and notarization, so macOS cannot verify the developer. Once you allow it, the warning does not appear again.

### Is it malware?

No. The full source code is on [GitHub](https://github.com/taehee33/magictrack202603), and you can build it yourself.

### Why is it not on the Mac App Store?

It needs private macOS features and runs outside the sandbox, which App Store rules do not allow.
