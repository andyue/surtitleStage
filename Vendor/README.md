# Syphon dependency

Official upstream: https://github.com/Syphon/Syphon-Framework
Pinned commit: f4761677a45b8034a3c2069ec0f3d2553da81fba

The checked-in Universal framework was built from that commit using Xcode, Release,
ARCHS="x86_64 arm64", macOS deployment target 14.0, no upstream code modifications.
Rebuild offline with Scripts/build-syphon.sh. The binary is signed as part of the app packaging step.

Source archive: Syphon-source-f476167.zip
SHA-256: 7ca4824406ae51aad1f357078f5979c79bb35f74099b6380feb21c400b5cdd60
Original URL: https://api.github.com/repos/Syphon/Syphon-Framework/zipball/f4761677a45b8034a3c2069ec0f3d2553da81fba

Why included: macOS Metal/IOSurface provide GPU surfaces but not Syphon's client discovery
and inter-process frame protocol. The official framework provides compatibility with Syphon clients.
The old SDK 5 release was examined but is not used; it predates this Metal/Apple Silicon implementation.

Licenses: Syphon-LICENSE.txt and Syphon-Metal-LICENSE.txt.
Both are shipped in the app's Resources. Full source copyright notices are retained in the archive.
NDI is not bundled, linked, or required.

## NDI headers / optional runtime

NDIBridge/SDK contains MIT-noticed Vizrt NDI headers from locally installed cyndilib 0.0.5 (Blender Python package). Each original notice is preserved; the app also includes NDI-Headers-LICENSE.txt. No NDI binary is vendored or redistributed. Runtime is loaded only on demand from an installed official runtime/tools or a user-selected library. See NDI.md for provenance, tested runtime and limitations. NDI® is a registered trademark of Vizrt NDI AB. https://ndi.video/
