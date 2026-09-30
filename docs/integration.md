# Integration

## Folder contents

`Sentinel` belongs in ServerScriptService. Config, Service, Policy, Validate, Evidence, Movement, RemoteGuard, and SmokeTests are ModuleScripts. Bootstrap is the only automatically running Script. The nested Signal folder provides the Discord transport; it has no Bootstrap and is started by Service. Examples are ModuleScripts and do not run automatically.

You do not need to install the separate Signal project. Having both projects running is possible but produces separate logger queues and startup messages.

## What works after insertion

Speed and large-displacement monitoring run for player Humanoid characters with HumanoidRootPart. Respawns start a grace window. Dead, anchored, and seated characters are skipped. Long server sampling gaps reset the baseline. Ping contributes a capped tolerance. Allowed speed is maintained by trusted server configuration, not read from the client's claimed WalkSpeed.

## What needs your code

Remote validation, interaction permissions, economy rules, inventory ownership, combat hit validation, vehicles, movement abilities, and purchase fulfillment require game-specific integration. This package does not magically intercept all remotes or validate every game mechanic.

### Remote API

`BindRemote(remote, options, handler)` accepts a RemoteEvent and returns an unbind function.

- `Rate`: token refill per second per player, default 5.
- `Burst`: token capacity, default 8.
- `ArgCount`: exact number of client arguments, default 1. The implicit Player is excluded.
- `Validate(player, ...)`: must return exactly `true` to run the handler.
- Handler and validator exceptions are logged as developer errors, not proof against the player.

Validators should be fast, non-yielding, and side-effect free. Avoid DataStore/network calls during validation. Handlers may yield but should finish; a permanently yielded handler holds that route/player lock until cleanup. Other guarded remotes have separate locks. Cross-remote transactions need a shared lock and idempotency in your game code.

Arguments are bounded before validation, but Roblox has already deserialized the packet when the handler receives it. This is not a transport-level packet firewall or protection against every resource-exhaustion attack.

### Validators

- `Number(min, max, integer)` rejects NaN and infinities.
- `String(maxBytes, optionalPattern)` enforces byte length and valid UTF-8. Anchor patterns with `^` and `$` if needed.
- `Enum({"a", "b"})` accepts only listed strings.
- `Boolean` is a predicate.
- `Vector3(maxMagnitude)` checks finite components and magnitude.
- `Object(schema)` requires known keys and validates missing values; use Optional for optional fields.
- `Optional(predicate)` accepts nil or a matching value.
- `Instance(className, ancestor)` requires both class and ancestry.

The basic payload filter accepts Instances as a type; always constrain them with a schema or, preferably, send a short ID that your server maps to a trusted object. CFrames, functions, cycles, and unsupported datatypes are rejected by the basic payload filter.

### Interactions

`IsNear(player, targetPart, distance)` checks an alive player and an in-workspace target. `HasLineOfSight` adds a server raycast. Use anchored/server-controlled targets: a client-owned unanchored part may be moved near the player. These checks cannot establish that the player's own position was reached legitimately. Add server progression, cooldown, ownership, and permission checks for consequential actions.

`Examples/Interaction` is an initializer. Require it and pass your existing RemoteEvent, a folder of uniquely named anchored targets, and your trusted handler. It does not create remotes or rewards. It replaces the old handler, not supplements it.

### Economy and purchases

Clients should request an action or item ID, never supply the awarded amount, price, balance, ownership, or receipt success. Determine those values server-side, check eligibility, and perform changes atomically. Call security logging after your existing purchase handler verifies fulfillment. Sentinel does not install or replace ProcessReceipt.

### Movement allowances

- `SetAllowedSpeed(player, speed)`: permanent detector budget for this player session, retained through respawns. Reset it when your sprint/class state changes.
- `AllowSpeedBoost(player, speed, seconds)`: temporary larger horizontal budget, up to 120 seconds. It does not exempt hovering or wall crossings.
- `AllowMovement(player, seconds, reason)`: suspends movement checks for up to 30 seconds; use before validated impulses, scripted movement, and custom mechanics.
- `Teleport(player, targetCFrame)`: grants two seconds of allowance before PivotTo. Target must come from the server.

Do not expose a remote that blindly forwards client-chosen speed, target, duration, or exemption reason. Existing allowance windows are detection gaps; keep them short.

### Configuration

Defaults target an ordinary walking character and must be tuned:

| Setting | Default |
| --- | --- |
| SampleInterval | 0.25 seconds |
| SpawnGrace | 5 seconds |
| DefaultMaxSpeed | 26 studs/second |
| SpeedWindow | 1.5 seconds |
| SpeedSlack | 8 studs per window |
| TeleportDistance | 80 studs per sample |
| PingAllowanceCap | 0.35 seconds |
| HoverEnabled / NoclipEnabled | false |
| ReportCooldown | 15 seconds per player/rule |
| ScoreHalfLife | 60 seconds |
| MaxEvidence | 30 entries per player |

Keep numeric settings finite and positive. Rates and payload limits apply to every bound route; customize route rates for actual game actions. Config is read at startup; restart the server after editing it.

## Discord

The entire framework runs server-side. The webhook is stored only in the server Config. Alerts include Roblox user ID, rule, score, and a short observation; raw remote payloads are not logged. The score can help prioritize review but is not a cheat probability.

The queue is capped at 200 records. Overload drops new events, retries are bounded, 429 delays are respected, and permanent access failures disable delivery until restart. A request timeout can cause a retry after the first request succeeded, producing duplicate messages. Multiple game servers share a webhook's quota; use your own relay or logging backend for scale.

Evidence is in memory and removed when players leave. Discord delivery is best effort, including during shutdown. This is not a permanent moderation audit database.
