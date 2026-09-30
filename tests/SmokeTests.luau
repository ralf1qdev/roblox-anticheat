return function()
    local Policy = require(script.Parent.Policy)
    local V = require(script.Parent.Validate)
    local Evidence = require(script.Parent.Evidence)
    local Guard = require(script.Parent.RemoteGuard)
    local config = table.clone(require(script.Parent.Config))
    local now, logs, groups = 0, {}, 0
    local function clock() return now end
    local logger = {
        Warn = function(_, event, message, detail) table.insert(logs, { event, detail }) end,
        Error = function(_, event) table.insert(logs, { event }) end,
    }
    local function check(condition, name) assert(condition, name) end
    local function group() groups = groups + 1 end
    check(not Policy.Finite(0/0) and not Policy.Finite(math.huge) and Policy.Finite(12), "finite numbers")
    check(V.Number(0, 10, true)(5) and not V.Number(0, 10, true)(5.5), "integer range")
    check(V.String(4)("test") and not V.String(4)("longer"), "string bound")
    check(V.Enum({"a", "b"})("b") and not V.Enum({"a"})("c"), "enum")
    group()
    local schema = V.Object({ id = V.String(10), count = V.Number(1, 5, true), note = V.Optional(V.String(5)) })
    check(schema({id="abc", count=2}), "schema success")
    check(not schema({id="abc", count=2, extra=true}) and not schema({id="abc"}), "schema extra/missing keys")
    group()
    local cycle = {}; cycle.self = cycle
    check(not V.Payload(cycle, config), "cycles rejected")
    check(not V.Payload({ x = 0/0 }, config), "NaN rejected")
    check(not V.Payload(string.rep("x", 513), config), "large strings rejected")
    check(not V.Payload({{{{{{1}}}}}}, config), "deep table rejected")
    local wide = {}; for i=1,100 do wide[i]=true end
    check(not V.Payload(wide, config), "wide table rejected")
    check(V.Payload({id="a",count=2}, config), "normal payload")
    group()
    local bucket
    local allowed
    allowed,bucket = Policy.Bucket(nil,0,2,2); check(allowed, "first token")
    allowed,bucket = Policy.Bucket(bucket,0,2,2); check(allowed, "burst token")
    allowed,bucket = Policy.Bucket(bucket,0,2,2); check(not allowed, "limit")
    allowed,bucket = Policy.Bucket(bucket,0.5,2,2); check(allowed, "refill")
    group()
    local function sample(time, x, y, grounded, exempt)
        return {time=time,x=x,y=y or 0,z=0,grounded=grounded ~= false,exempt=exempt or false,maxSpeed=26,ping=0}
    end
    local state = Policy.NewMovement()
    check(#Policy.Movement(state,sample(0,0),config)==0, "baseline")
    check(#Policy.Movement(state,sample(1,16),config)==0, "normal speed")
    check(#Policy.Movement(state,sample(2,32),config)==0, "normal window")
    group()
    state = Policy.NewMovement()
    Policy.Movement(state,sample(0,0),config)
    Policy.Movement(state,sample(0.75,35),config)
    local result = Policy.Movement(state,sample(1.5,70),config)
    check(#result==1 and result[1].rule=="movement.speed", "speed detection")
    result = Policy.Movement(state,sample(1.75,200),config)
    check(result[1].rule=="movement.teleport", "teleport detection")
    group()
    check(#Policy.Movement(state,sample(2,1000,0,true,true),config)==0, "authorized movement")
    check(#Policy.Movement(state,sample(10,5000),config)==0, "long sample gap resets")
    check(Policy.Movement(state,sample(11,math.huge),config)[1].rule=="movement.invalid", "invalid position")
    group()
    local hover = table.clone(config); hover.HoverEnabled=true; hover.HoverSeconds=2
    state=Policy.NewMovement(); Policy.Movement(state,sample(0,0,30,false),hover)
    Policy.Movement(state,sample(1,0,30,false),hover)
    result=Policy.Movement(state,sample(2,0,30,false),hover)
    check(result[1].rule=="movement.hover", "hover sustained")
    state=Policy.NewMovement(); Policy.Movement(state,sample(0,0,30,false),hover)
    check(#Policy.Movement(state,sample(1,0,10,false),hover)==0, "falling not hovering")
    group()
    local player={UserId=123}
    local evidence=Evidence.new(config,logger,clock)
    check(evidence:Add(player,"movement.speed","test"), "evidence recorded")
    check(not evidence:Add(player,"movement.speed","repeat"), "duplicate cooldown")
    check(evidence:Get(player).score==8, "duplicate does not inflate score")
    now=60
    check(math.abs(evidence:Get(player).score-4)<0.001, "score half life")
    local copy=evidence:Get(player); copy.recent[1].detail="changed"
    check(evidence:Get(player).recent[1].detail=="test", "defensive snapshot")
    evidence:Remove(player); check(evidence:Get(player).score==0, "cleanup")
    group()
    local strict=table.clone(config); strict.MaxEvidence=2
    local bounded=Evidence.new(strict,logger,clock)
    for i=1,5 do now=now+16; bounded:Add(player,"movement.speed","bounded") end
    check(#bounded:Get(player).recent==2, "evidence ring bound")
    group()
    local guard=Guard.new(config,evidence,logger,clock)
    local calls=0
    local route={name="Test",rate=10,burst=10,argCount=1,buckets={},busy={},removed={},closed=false,
        validate=function(_,payload) return schema(payload) end,
        handler=function() calls=calls+1; return "ok" end}
    local passed,value=guard:_process(route,player,table.pack({id="a",count=2}))
    check(passed and value=="ok" and calls==1, "guard allowed")
    check(not guard:_process(route,player,table.pack({id="a",count=0/0})) and calls==1, "bad payload no action")
    check(not guard:_process(route,player,table.pack({id="a",count=8})) and calls==1, "bad schema no action")
    check(not guard:_process(route,player,table.pack({},{})) and calls==1, "argument arity")
    group()
    route.busy[player]=true
    check(not guard:_process(route,player,table.pack({id="a",count=2})) and calls==1, "in-flight rejection")
    route.busy[player]=nil
    route.validate=function() error("test") end
    check(not guard:_process(route,player,table.pack({id="a",count=2})) and calls==1, "validator error fails closed")
    check(not route.busy[player], "lock released")
    route.validate=function() return true end
    route.handler=function() error("test") end
    check(not guard:_process(route,player,table.pack({})) and not route.busy[player], "handler failure releases lock")
    group()
    local callback
    local disconnected=false
    local remote={Name="Bound",IsA=function(_,name) return name=="RemoteEvent" end,
        OnServerEvent={Connect=function(_,fn) callback=fn; return {Disconnect=function() disconnected=true end} end}}
    local unbind=guard:Bind(remote,{Validate=function() return true end},function() calls=calls+1 end)
    callback(player,{})
    check(calls==2, "binding routes callback")
    guard:Remove(player)
    callback(player,{})
    check(calls==2, "removed players rejected")
    unbind(); check(disconnected and guard.Count==0, "unbind cleanup")
    group()
    check(groups==13,"test group count")
    print("[Sentinel tests] " .. groups .. " groups passed; no HTTP requests or enforcement.")
    return true
end
