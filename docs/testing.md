# Testing and limitations

## Verification performed

13 core groups ran using a Lua runtime with mocked Roblox services:

1. Finite numeric, integer, string, and enum constraints
2. Required/optional schema fields and extra-key rejection
3. Payload cycles, depth, width, string size, and NaN rejection
4. Token-bucket exhaustion and refill
5. Normal movement samples
6. Sustained speed and large-displacement findings
7. Movement exemptions, long-gap reset, and non-finite positions
8. Hover threshold and falling exclusion
9. Evidence cooldown, score decay, snapshot isolation, and cleanup
10. Bounded evidence history
11. Guard acceptance, payload rejection, schema rejection, and argument count
12. Concurrent-handler rejection and exception cleanup
13. Remote binding, player removal, and unbinding

All supplied Luau sources were parsed as Lua-compatible code. That check does not verify Roblox API behavior. The Discord transport is adapted from Signal, whose separate mock-service tests cover retries, rate limits, redaction, and queue behavior. No live webhook was contacted while creating this package.

## Required Studio checks

1. Insert the model into a blank test place and confirm ServerScriptService/Sentinel exists once.
2. Run the included SmokeTests from the server Command Bar.
3. Confirm normal walking, jumping, stairs, slopes, falling, death, and respawn do not create sustained false findings.
4. Repeat with Studio's Network Simulator using realistic latency and packet loss.
5. Test vehicles, conveyors, moving platforms, swimming, climbing, launch pads, and every movement ability. Add narrow server-authorized allowances as needed.
6. Use a server-side test teleport to a far position without an allowance, then repeat using Service:Teleport. The first may produce a monitor finding; the authorized one should not.
7. Connect a test RemoteEvent only through BindRemote. Send a valid payload, an invalid payload, and a burst. Verify only valid, in-budget requests reach your harmless test handler.
8. Verify the Discord message has a user ID and evidence and does not include the webhook URL or raw payload.
9. Test simultaneous players and inspect performance using Roblox's server profiler.

Run disruptive tests only in a private test place. Do not send synthetic abuse to other developers' games.

## Limits

There are no automatic kicks, bans, movement corrections, permanent player records, client scanners, injected-code detectors, or claims to detect every cheat.

Movement is client-replicated and sampled. Exploiters can stay below thresholds, move between samples, or exploit exemptions. Seated/anchored characters and spawn grace are intentionally unmonitored. Normal moving platforms and legitimate forces may exceed generic thresholds. Hover and wall-crossing detection are heuristics, disabled by default. Wall raycasts can flag doors or moving geometry, and cannot establish whether a player truly passed through a wall.

The framework cannot reliably detect ESP, aimbots, or code running on a player's device. It cannot secure client-authoritative currency, damage, or inventory by observing movement. Critical game state must be validated and maintained on the server.

Monitoring scores are indicators, not proof of cheating. A high score must not automatically become a moderation decision without game-specific review and testing.

No software license has been selected. Add one before offering reuse under specific open-source terms.

## References

- https://create.roblox.com/docs/scripting/security/security-tactics
- https://create.roblox.com/docs/scripting/security/client-server-boundary
- https://create.roblox.com/docs/scripting/security/network-ownership
- https://create.roblox.com/docs/reference/engine/classes/Player
- https://create.roblox.com/docs/workspace/raycasting
- https://docs.discord.com/developers/topics/rate-limits
