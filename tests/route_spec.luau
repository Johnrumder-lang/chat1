-- Run via python3 tests/run_route_spec.py <path-to-luau>.
-- Roblox-only Vector3/CFrame are represented by mathematical equivalents here.
-- Noise is bounded deterministic test input, not an assertion about Roblox's noise implementation.
local V = {}
local VMeta = {}
VMeta.__index = function(self, key)
	if key == "Magnitude" then return math.sqrt(self.X^2 + self.Y^2 + self.Z^2) end
	if key == "Unit" then return self / self.Magnitude end
	return V[key]
end
VMeta.__add = function(a,b) return Vector3.new(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
VMeta.__sub = function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
VMeta.__unm = function(a) return Vector3.new(-a.X,-a.Y,-a.Z) end
VMeta.__mul = function(a,b)
	if type(a) == "number" then a,b=b,a end
	return Vector3.new(a.X*b,a.Y*b,a.Z*b)
end
VMeta.__div = function(a,b) return Vector3.new(a.X/b,a.Y/b,a.Z/b) end
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
function V:Cross(b) return Vector3.new(self.Y*b.Z-self.Z*b.Y,self.Z*b.X-self.X*b.Z,self.X*b.Y-self.Y*b.X) end
Vector3 = {}
function Vector3.new(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0},VMeta) end
Vector3.yAxis = Vector3.new(0,1,0)
local CFMeta = {}
CFMeta.__index = CFMeta
local function frame(p, right, up, look)
	return setmetatable({Position=p,RightVector=right,UpVector=up,LookVector=look},CFMeta)
end
local function transformDirection(cf,p)
	return cf.RightVector*p.X + cf.UpVector*p.Y - cf.LookVector*p.Z
end
function CFMeta:PointToWorldSpace(p) return self.Position+transformDirection(self,p) end
CFMeta.__mul = function(a,b)
	return frame(a:PointToWorldSpace(b.Position),transformDirection(a,b.RightVector),transformDirection(a,b.UpVector),transformDirection(a,b.LookVector))
end
CFrame = {}
function CFrame.new(x,y,z)
	local p = if type(x)=="table" then x else Vector3.new(x,y,z)
	return frame(p,Vector3.new(1,0,0),Vector3.new(0,1,0),Vector3.new(0,0,-1))
end
function CFrame.lookAt(p,target,up)
	local look=(target-p).Unit
	local right=look:Cross(up or Vector3.yAxis).Unit
	return frame(p,right,right:Cross(look).Unit,look)
end
local noiseMode = "smooth"
local testMath = table.clone(math)
testMath.noise = function(x,y,z)
	if noiseMode == "high" then return 0.5 end
	if noiseMode == "low" then return -0.5 end
	return math.sin(x*1.3+y*0.7+z*0.031)*math.cos(y*1.1-x*0.3)*0.48
end
local math = testMath
-- ROUTE_MODULE

local checks = 0
local function check(condition, message)
	checks += 1
	assert(condition, message)
end
local first = Route.sample(0)
check((first.Position - Vector3.new(0,32,0)).Magnitude < 1e-8,"start must be (0,32,0)")
check(Route.roadHalfWidth == 15,"car clearance expects 30-stud road")
check(first.LookVector.Z < -0.95,"route faces -Z")

local maxGrade,maxTurning = 0,0
for distance=-Route.period*2,Route.period*12,4 do
	local cf=Route.sample(distance)
	local nextCF=Route.sample(distance+16)
	local delta=nextCF.Position-cf.Position
	local grade=math.abs(delta.Y)/math.sqrt(delta.X^2+delta.Z^2)
	local turning=math.acos(math.clamp(cf.LookVector:Dot(nextCF.LookVector),-1,1))
	maxGrade=math.max(maxGrade,grade)
	maxTurning=math.max(maxTurning,turning)
	check(grade<0.04,"road grade exceeds suspension-friendly 4%")
	check(turning<0.012,"16-stud seam curvature exceeds overlap allowance")
	check(math.abs(cf.Position.Z+distance)<1e-8,"distance must map to -Z")
	check(cf.Position.Y>Route.waterHeight+2.5,"road surface must remain above the global water plane")
	check(math.abs(cf.LookVector.Magnitude-1)<1e-8,"frame basis must be orthonormal")
	local spawn=Route.spawn(distance,6.5)
	local expected=cf:PointToWorldSpace(Vector3.new(6.5,3.4,0))
	check((spawn.Position-expected).Magnitude<1e-8,"spawn transform mismatch")
	local surface=Route.surface(distance)
	check(surface=="Bridge" or surface=="Asphalt" or surface=="Dirt","unknown road material")
	if distance % 256 == 0 then
		local seam=(Route.sample(distance-0.0001).Position-Route.sample(distance+0.0001).Position).Magnitude
		check(seam<0.00022,"chunk seam discontinuity")
	end
end

for _,mode in ipairs({"low","smooth","high"}) do
	noiseMode=mode
	for distance=-Route.period,Route.period*4,8 do
		local road=Route.sample(distance)
		for _,lateral in ipairs({-14,0,14}) do
			local point=road:PointToWorldSpace(Vector3.new(lateral,0,0))
			local h=Route.height(point.X,point.Z)
			check(h<point.Y-0.55,"terrain clips road: d="..distance.." lateral="..lateral.." mode="..mode)
			check(h>-60 and h<384,"terrain exceeds owned chunk vertical bounds")
		end
	end
end

for cycle=-3,6 do
	local riverD=cycle*Route.period+1048
	check(Route.surface(riverD)=="Bridge","river crossing must have bridge")
	local cf=Route.sample(riverD)
	check(Route.height(cf.Position.X,cf.Position.Z)<Route.waterHeight,"river must be underwater below bridge")
	for _,edge in ipairs({943.9,1152.1}) do
		local d=cycle*Route.period+edge
		local p=Route.sample(d).Position
		check(math.abs(Route.height(p.X,p.Z)-(p.Y-0.75))<0.00001,"bridge approach must join road bank")
	end
	local lakeD=cycle*Route.period+390
	local lakeX=Route.centerX(lakeD)+(if cycle%2==0 then 205 else -205)
	check(Route.height(lakeX,-lakeD)<Route.waterHeight-4,"lake basin must hold water")
end
print(string.format("Route: %d assertions passed; max grade %.3f%%, max 16-stud turn %.3f degrees",checks,maxGrade*100,math.deg(maxTurning)))
