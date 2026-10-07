# Studio playtest

Open `dist/Northbound.rbxlx`, open **View → Output**, and use **Play (F5)** rather than Run so the player, camera, controls and GUI initialize.

1. The edit-mode scene should show the sage Aster wagon. In Play, the loading menu should remain until terrain and the local supporting road are available. The wagon remains anchored until Begin journey.
2. Begin. Confirm the character is R6, the camera sits inside the cabin, and the car settles evenly on all four tyres without a sustained bounce. Test acceleration, braking to a halt, reverse, low-speed full-lock steering and high-speed steering.
3. Press H twice. Both headlight beams should switch off/on. Hold right mouse to inspect the cabin; release to recenter. Confirm the steering wheel and instrument needles move with the car.
4. Drive north. A lake appears beside the route near distance 390 studs, a river bridge between 944 and 1152, and a dirt section between 1888 and 2688. Keep driving through several chunks. Check seams, shoulders, bridge rails and tyre contact. These feature regions repeat with procedural terrain variations every 3072 studs.
5. Stop near a deer and watch the subtle grazing movement. Bird flocks should circle outside the immediate driving area.
6. Wait for the weather cycle: Clear lasts 150 seconds, then Overcast 85, then Rain 140, with 35-second transitions. Check clouds, rain outside the roof, wipers and reduced grip. Fog and a later storm follow. Daylight advances gradually.
7. Drive off-road and press R. The car and seated character should return together to the nearby road. Reset the avatar through the Roblox menu and confirm reseating works.
8. In Explorer watch `Workspace.Scenery` attributes and child chunks. Generation should move forward and remove distant chunks; `GeneratedChunks` must not exceed the configured cap. `GenerationError` should remain absent.
9. Test a smaller viewport and Studio's device emulator. Touch pedals must not overlap Roblox's default character controls. Run a two-client test before enabling multiplayer; inspect car ownership, seating and streaming for separated drivers.

Inspect Output after every failure and record the message, location and input. Avoid treating a compile pass or the offline model render as a Roblox runtime pass. Set the published experience's Avatar setting to R6 and begin with Max Players = 1 until multiplayer and performance are verified.

For visual tuning, use the highest practical Studio graphics quality, then reduce it to the target device's normal level. Tune `treeDensity`, `terrainHalfWidth` and `maxChunks` in the World constructor only after measuring performance. Wider terrain and longer draw distances cost memory and generation time.
