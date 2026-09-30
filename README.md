# Sentinel

A server-side Roblox security framework built with Luau. Movement monitoring, guarded RemoteEvents, evidence tracking, and Discord alerts.

**Monitor mode:** movement findings never kick, ban, or reposition players. Guarded remotes reject invalid requests before running your handler.

## Features

- Sustained speed and large displacement checks
- Temporary allowances for teleports, knockback, and speed boosts
- Optional hover and wall-crossing heuristics
- Per-player, per-remote token-bucket rate limits
- Payload depth, size, type, and finite-number checks
- Explicit schema and permission validation
- One in-flight handler per player per guarded remote
- Decaying scores and bounded evidence history
- Batched Discord alerts with retries and cooldowns

## Setup

1. Insert `Sentinel.rbxmx` into `ServerScriptService`.
2. Open `Sentinel → Config` and set `WebhookUrl` to your full Discord webhook URL.
3. Enable **Allow HTTP Requests** in your experience's Security settings.
4. Start a new Studio test. `StudioDelivery = true` sends test alerts to Discord.
5. Set `DefaultMaxSpeed` for your game and integrate legitimate movement abilities before interpreting findings.

Keep your real webhook URL out of GitHub. The supplied config is blank. Output logging works without Discord; network restrictions may require the optional [relay](relay/README.md).

## Protect a RemoteEvent

Replace the remote's existing gameplay connection with this pattern:

```lua
local sentinel = require(game.ServerScriptService.Sentinel.Service).Get()
local V = sentinel.Validate
local remote = game.ReplicatedStorage.RequestAction
local schema = V.Object({ action = V.Enum({ "Inspect", "Interact" }) })

sentinel:BindRemote(remote, {
    Rate = 3,
    Burst = 5,
    ArgCount = 1,
    Validate = function(player, payload)
        return schema(payload) and player.Character ~= nil
    end,
}, function(player, payload)
    print(player.Name, payload.action)
end)
```

The handler above only prints. For gameplay actions, validate permissions, alive state, ownership, distance, cooldowns, and server-maintained state before changing anything.

**A guard cannot block a separate `OnServerEvent` connection.** Remove or migrate the old handler. Unguarded remotes are unchanged.

## Legitimate movement

```lua
local sentinel = require(game.ServerScriptService.Sentinel.Service).Get()

sentinel:SetAllowedSpeed(player, 30)
sentinel:AllowSpeedBoost(player, 70, 3)
sentinel:AllowMovement(player, 2, "server knockback")
sentinel:Teleport(player, workspace.SpawnLocation.CFrame + Vector3.new(0, 4, 0))
```

Call these from server gameplay code, using server-chosen values. They are not client remotes. `SetAllowedSpeed` changes the detector budget, not the character's movement speed.

## Review findings

```lua
local snapshot = sentinel:GetEvidence(player)
print(snapshot.score, snapshot.observations)
print(sentinel:GetStats().remotes.rejected)
```

Scores represent heuristics, not proof. Tune and playtest before using reports for moderation. Hover and wall-crossing checks are disabled by default.

## Tests

From Studio's server Command Bar:

```lua
require(game.ServerScriptService.Sentinel.SmokeTests)()
```

13 core test groups passed with mocked Roblox services. Live movement, model import, and Discord delivery still need testing in your experience.

[Integration guide](docs/integration.md) · [Testing and limitations](docs/testing.md)
