# Reference capabilities and implementation boundaries

Reviewed 2026-10-29 against the current Apple listing and this repository's source.
This is an engineering specification for an independent implementation. Commercial
product claims below are advertised capabilities, not independently measured results.

## Primary sources

- [Dot3D App Store listing](https://apps.apple.com/us/app/dot3d-precision-lidar-scanner/id1641016966):
  Apple lookup returned version 6.5.0, bundle `com.dotproduct.dot3d`, minimum iOS 14.
- [Apple ARKit scene reconstruction sample](https://developer.apple.com/documentation/arkit/visualizing-and-interacting-with-a-reconstructed-scene):
  the native iOS sample configures `meshWithClassification`, receives mesh anchors,
  and demonstrates surface raycasts. This establishes the public API approach used
  here; it does not establish surveying accuracy or unlimited capture size.

The authorized App Store download attempt failed during authentication and produced
no IPA. There is no binary disassembly, recovered source, or inspected FairPlay status.
The comparison uses public product descriptions and original source written for OpenScan.

## Capability mapping

| Advertised reference capability | OpenScan implementation and limits |
| --- | --- |
| Live LiDAR scanning | ARKit mesh anchors; capture requires runtime scene reconstruction support. |
| On-device processing | Capture, serialization, and library storage are local; no application backend. |
| Large captures and loop closure | No independent registration/optimization engine or size guarantee. ARKit tracking alone does not verify these claims. |
| Reference targets | No coded targets, scale calibration, or survey control. |
| GNSS and coordinate systems | No receiver integration; exports use ARKit's local frame in meters, Y-up. |
| Appending scans | No persisted world map or cross-session registration. Pause/resume is within the current session. |
| Measurements and volume | No point selection, saved dimensions, or volume computation. Library dimensions describe the bounding box only. |
| Annotations and photos | No spatial annotation or image attachment model. |
| Cropping and hiding | No mesh selection/editing tools. |
| Color point-cloud formats | Since `e7fd466`, camera RGB is projected from ARFrames onto mesh vertices (`ColorAccumulator`, spatial-hash keyed so it survives ARKit re-meshing) and written per vertex in PLY, OBJ (`v x y z r g b`) and USDZ. Vertices the camera never saw are neutral gray; scans with no camera color fall back to classification colors on PLY faces. The projection math and exporters are unit-tested; color quality on a real LiDAR device is unverified. No UV texture atlas. No DP/E57/LAS/LAZ/PTS/PTX/PTG serializers. |
| Orthophotos and BIM integrations | No image projection, georeferencing, or service connector. |
| Frame exports for reconstruction tools | No synchronized RGB/depth/camera-pose dataset export. |
| Viewing on devices without LiDAR | Local saved USDZ files use Quick Look. Importing another device's scan into the library is not implemented. |

## Native architecture

`ScanSession` owns the AR session and current mesh-anchor collection. `snapshot()`
copies mesh geometry into world-space `MeshChunk` values. `ScanMesh` combines chunks
and calculates bounds. `MeshExporter` writes binary little-endian PLY, OBJ, and a
USDA scene packaged by `USDZPackager` as an uncompressed, aligned ZIP archive.

`ScanStore` writes each scan's exports and JSON metadata to a UUID directory under
Documents/Scans. `LibraryView` lists metadata, opens Quick Look, and shares individual
exports. File sharing exposes the Documents directory in Files. There is no account,
analytics client, subscription, or network service in the app source.

The app targets iOS/iPadOS 17 and both phone and tablet families. Unsupported devices
display an unavailable state for capture. Hardware capability is checked at runtime,
rather than inferred from a device name. Camera permission is declared in Info.plist.

## Evidence and limits

Candidate `a5de651b14db6c7c3ff5453518b9bd764bd7641d`:

- Simulator tests completed: 11 passed, including mesh merging, formats, ZIP alignment,
  CRC, bounds, and library persistence.
- A macOS command-line probe compiled the same three format serializers and exported
  a synthetic triangle in all formats. Apple's installed `usdchecker` returned
  `Success!` for that USDZ. This validates the fixture, not every possible scan.
- Physical iPhone development build, installation, and launch succeeded. Startup logs
  were captured; live mesh acquisition, spatial accuracy, long-session behavior, and
  a complete physical capture/save/preview workflow remain unverified.
- Simulator capture showed the unsupported-device state and both tabs after launch
  settled. A simulator cannot prove LiDAR behavior.
- Privacy preflight reported GREENLIT. A Release archive succeeded, signed for
  development. Neither result proves distribution readiness.

Candidate `e7fd466` (per-vertex camera color):

- Simulator tests: 31 passed, including camera projection (axis conventions with hand-computed
  pixels), BT.601 conversion, color-grid best-sample/drift behavior, and colored PLY/OBJ/USDA output.
- A deliberate Y-axis flip in `CameraProjector` made `testAboveCameraLandsAboveCenterBecauseImageYPointsDown`
  fail (600 vs 200), so the projection tests can detect that defect.
- Apple's `usdchecker` returned `Success!` on a vertex-colored USDZ fixture.
- Not verified: `ColorAccumulator` against a live `ARFrame`, color alignment with the real camera,
  and throughput on a long scan. These need a physical LiDAR device.

## Distribution constraints

As of 2026-10-29, App Store Connect returned no app for `com.esbeinc.openscan`.
The bundle-ID endpoint returned `PLA Update available`, requiring the Account Holder
to accept the latest Program License Agreement. An explicit App Store export attempt
returned exit 70: `No Accounts` and no matching iOS App Store provisioning profile.
No distribution IPA was produced, uploaded, processed, or assigned to testers.

After account access is restored, distribution requires a registered bundle ID,
App Store Connect app record, distribution signing/profile, unused build identity,
successful IPA export and validation, and the intended internal tester group.
The uploaded build must be verified as processed and assigned before calling it
available in TestFlight. Legal agreement acceptance is an Account Holder action.
