<!-- SPDX-FileCopyrightText: 2026 Nick Wolff <nick@wolff.tech> -->
<!-- SPDX-License-Identifier: GPL-2.0-only -->

# Logo Glow artwork

The icon depicts a centered, straight-on graphite laptop lid with a glowing white orb.
Its cool white halo fades across the metal against a charcoal background.

- `LogoGlow.icon` is the editable Apple Icon Composer document.
- `LogoGlow.png` is the 1024 × 1024 macOS export rendered with Apple's `ictool`.

The document separates the orb from the enclosure and its halo. Icon Composer
lists groups and layers from front to back. The enclosure and orb are SVGs;
the halo is a transparent PNG to preserve its smooth falloff in the renderer.

To regenerate the PNG from the repository root with Xcode 27 selected:

```sh
./Scripts/export-icon.sh
```

`Scripts/make-app.sh` compiles `LogoGlow.icon` into the app bundle's icon.
The menu bar icon is a monochrome template version of the lid and orb, drawn
in code in `Sources/LogoGlow/MenuBarController.swift`.
