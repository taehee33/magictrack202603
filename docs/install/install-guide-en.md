# MagicTrack Installation Guide

This guide explains how users can install and run MagicTrack on macOS.

Important:

- Some distributed builds may not yet be signed with an Apple Developer ID certificate.
- In that case, macOS may show stronger security warnings on first launch.

## 1. Download

Download one of the following files from the release page:

- Recommended: `.dmg`
- Alternative: `.zip`

## 2. Install

### Install from DMG

1. Double-click the `.dmg` file
2. Drag `MagicTrack.app` into the `Applications` folder
3. Open `Applications` and confirm the app is there

### Install from ZIP

1. Double-click the `.zip` file
2. Locate the extracted `MagicTrack.app`
3. Move it into the `Applications` folder

Recommendation:

- Run the app from `Applications`
- Do not run it directly from `Downloads`

## 3. First Launch

If the app opens normally, you should see the app window or the menu bar icon.

If the build is not signed/notarized yet, macOS may show warnings such as:

- Unidentified developer
- Apple cannot verify this app
- The app cannot be opened for security reasons

## 4. Best First Attempt

1. Open the `Applications` folder
2. Right-click `MagicTrack.app`
3. Click `Open`
4. Click `Open` again if macOS asks for confirmation

This works better than double-clicking for unsigned builds.

## 5. If the App Still Does Not Open

### Method A: Allow from System Settings

1. Open `System Settings`
2. Go to `Privacy & Security`
3. Scroll down
4. Look for a blocked app message related to `MagicTrack`
5. Click `Open Anyway`

Then try launching the app again.

### Method B: Try Right-Click > Open Again

In some cases:

1. Launch is blocked once
2. The second attempt using right-click > open succeeds

## 6. Permissions

MagicTrack may require macOS permissions for some features.

### Input Monitoring

May be needed for:

- Trackpad configuration related behavior

Path:

1. `System Settings`
2. `Privacy & Security`
3. `Input Monitoring`
4. Enable `MagicTrack`

### Accessibility

May be needed for:

- App auto-switching behavior

Path:

1. `System Settings`
2. `Privacy & Security`
3. `Accessibility`
4. Enable `MagicTrack`

After changing permissions, relaunching the app is recommended.

## 7. Basic Usage

### Trackpads tab

- Adjust internal trackpad settings
- Adjust Magic Trackpad settings
- Apply settings manually

### Presets tab

- Save current settings
- Apply saved presets

### Settings tab

- Enable or disable app auto-switching
- Show or hide the app in the Dock while running
- Show or hide the app in the menu bar while running

### Quick switching

- Shortcut: `option + M`
- Quickly switch between internal and Magic Trackpad profiles

## 8. Current Limitations

- Real-time raw input detection for Apple trackpads is not supported
- Coordinate and gesture detection are not supported
- Input-driven automation is not supported
- Magic Trackpad rotation is currently experimental
- Full real-time independent sensitivity control is limited by Apple platform behavior

## 9. Troubleshooting Checklist

1. Make sure the app is in `Applications`
2. Try right-click > `Open`
3. Check `Privacy & Security > Open Anyway`
4. Grant Input Monitoring / Accessibility if requested
5. Quit and relaunch the app

## 10. Why This Happens

Unsigned builds are treated more strictly by macOS Gatekeeper.

For a smoother public release, the app should eventually be distributed with:

- Apple Developer Program membership
- Developer ID Application certificate
- notarization

