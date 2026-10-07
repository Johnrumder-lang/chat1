#!/usr/bin/env python3
"""Execute the real Luau suspension/tyre controller against a flat-road rigid-body mock.

Usage: python tests/vehicle_spec.py --luau /path/to/luau
This validates forces and integration; Roblox Studio remains necessary for engine,
network ownership, collision solver, and articulated avatar integration.
"""
from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
MOCKS = r'''
local V = {}
V.__index = function(self, key)
 if key == "Magnitude" then return math.sqrt(self.X*self.X+self.Y*self.Y+self.Z*self.Z) end
 if key == "Unit" then return self / self.Magnitude end
 return V[key]
end
local function vec(x,y,z) return setmetatable({X=x or 0,Y=y or 0,Z=z or 0}, V) end
V.__add = function(a,b) return vec(a.X+b.X,a.Y+b.Y,a.Z+b.Z) end
V.__sub = function(a,b) return vec(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end
V.__unm = function(a) return vec(-a.X,-a.Y,-a.Z) end
V.__mul = function(a,b) if type(a)=="number" then return b*a end return vec(a.X*b,a.Y*b,a.Z*b) end
V.__div = function(a,b) return vec(a.X/b,a.Y/b,a.Z/b) end
function V:Dot(b) return self.X*b.X+self.Y*b.Y+self.Z*b.Z end
function V:Cross(b) return vec(self.Y*b.Z-self.Z*b.Y,self.Z*b.X-self.X*b.Z,self.X*b.Y-self.Y*b.X) end
local Vector3 = {new=vec}
local CF = {}
CF.__index = CF
CF.__mul = function(a,b) return a end -- Rotation composition is only used for visual wheel transforms.
local function cf(x,y,z)
 return setmetatable({Position=vec(x,y,z),LookVector=vec(0,0,-1),UpVector=vec(0,1,0)}, CF)
end
function CF:PointToWorldSpace(v) return self.Position+v end
function CF:VectorToWorldSpace(v) return v end
function CF:VectorToObjectSpace(v) return v end
local CFrame = {new=cf, Angles=function() return cf() end}
local Enum = {RaycastFilterType={Exclude=1},Material={Water=1,Ground=2,Mud=3,Sand=4,Asphalt=5}}
local RaycastParams = {new=function() return {} end}
local rain = 0
local Workspace = {Gravity=196.2,road=true}
function Workspace:FindFirstChild() return nil end
function Workspace:Raycast(origin,direction)
 if not self.road or origin.Y > -direction.Y or origin.Y < 0 then return nil end
 return {Distance=origin.Y,Normal=vec(0,1,0),Position=vec(origin.X,0,origin.Z),Material=Enum.Material.Asphalt}
end
local Players = {GetPlayers=function() return {} end}
local ReplicatedStorage = {FindFirstChild=function() return {GetAttribute=function() return rain end} end}
local game = {GetService=function(_,name)
 return ({Workspace=Workspace,Players=Players,ReplicatedStorage=ReplicatedStorage})[name]
end}
'''
TESTS = r'''
local function newModel(y)
 local root = {Name="Chassis",Parent=true,Anchored=false,AssemblyMass=100,
  CFrame=cf(0,y or 2,0),AssemblyLinearVelocity=vec(),AssemblyAngularVelocity=vec(), impulses={}}
 function root:IsA(name) return name=="BasePart" end
 function root:GetVelocityAtPosition() return self.AssemblyLinearVelocity end
 function root:ApplyImpulse(impulse)
  assert(impulse.Magnitude == impulse.Magnitude, "NaN impulse")
  self.AssemblyLinearVelocity += impulse/self.AssemblyMass
  table.insert(self.impulses,impulse)
 end
 function root:ApplyImpulseAtPosition(impulse, _) self:ApplyImpulse(impulse) end
 function root:ApplyAngularImpulse() end
 local model = {attributes={},descendants={},root=root}
 -- Place identically named Motor6Ds before hubs, matching XML descendant ordering.
 for _,name in ipairs({"WheelFL","WheelFR","WheelRL","WheelRR"}) do
  local part={Name=name,IsA=function(_,kind) return kind=="BasePart" end}
  local motor={Name=name,Part1=part,IsA=function(_,kind) return kind=="Motor6D" end}
  table.insert(model.descendants,motor)
  table.insert(model.descendants,part)
 end
 function model:FindFirstChild(name) if name=="Chassis" then return root end
  for _,v in ipairs(self.descendants) do if v.Name==name then return v end end
 end
 function model:GetDescendants() return self.descendants end
 function model:SetAttribute(key,value) self.attributes[key]=value end
 return model
end
local function tick(controller,dt,throttle,steer,handbrake,integrate)
 local root=controller.root
 controller:step(dt,throttle or 0,steer or 0,handbrake or false)
 root.AssemblyLinearVelocity += vec(0,-Workspace.Gravity*dt,0)
 if integrate then
  root.CFrame=cf(0,root.CFrame.Position.Y+root.AssemblyLinearVelocity.Y*dt,0)
 else
  root.CFrame=cf(0,2,0)
  root.AssemblyLinearVelocity=vec(root.AssemblyLinearVelocity.X,0,root.AssemblyLinearVelocity.Z)
 end
end
for _,fps in ipairs({30,60,120}) do
 local model=newModel(3.4)
 local controller=VehiclePhysics.new(model)
 for i=1,fps*10 do tick(controller,1/fps,0,0,false,true) end
 assert(math.abs(model.root.CFrame.Position.Y-2)<.07,"Spring does not settle at correct ride height")
 assert(math.abs(model.root.AssemblyLinearVelocity.Y)<.07,"Spring does not damp vertical oscillation")
 assert(#controller.wheels==4 and controller.wheels[1].motor,"Motor name collision breaks wheel lookup")
 assert(model.attributes.GroundedWheels==4,"Four ground contacts required")
 print("PASS: spring settling and motor binding at "..fps.." Hz")
end
local model=newModel()
local controller=VehiclePhysics.new(model)
for i=1,60*15 do tick(controller,1/60,1,0,false,false) end
local achieved=-model.root.AssemblyLinearVelocity.Z
assert(achieved>130 and achieved<VehiclePhysics.Config.ForwardLimit+1,"Forward acceleration or speed limit broken")
print("PASS: forward acceleration and terminal speed",achieved)
-- Reverse is first a brake; it should not instantly reverse or add forward velocity.
local before=-model.root.AssemblyLinearVelocity.Z
tick(controller,1/60,-1,0,false,false)
assert(-model.root.AssemblyLinearVelocity.Z<before,"Reverse throttle must brake forward movement")
for i=1,60*8 do tick(controller,1/60,-1,0,false,false) end
assert(model.root.AssemblyLinearVelocity.Z>8 and model.root.AssemblyLinearVelocity.Z<31,"Reverse gear must engage and respect reverse limit")
print("PASS: reverse throttle brakes, then engages reverse")
model.root.AssemblyLinearVelocity=vec(0,0,-60)
for i=1,60*3 do tick(controller,1/60,0,0,true,false) end
assert(math.abs(model.root.AssemblyLinearVelocity.Z)<1,"Handbrake should stop vehicle")
print("PASS: handbrake stops vehicle")
model.root.AssemblyLinearVelocity=vec(0,0,-35)
for i=1,15 do tick(controller,1/60,0,1,false,false) end
assert(model.root.AssemblyLinearVelocity.X>1,"Right steering must produce rightward tyre force")
assert(controller.wheels[1].motor.C0.Position.Y<0,"Suspension visual hub position invalid")
print("PASS: steering direction and wheel suspension position")
local function lateralAfterStep(precipitation)
 rain=precipitation
 local tractionModel=newModel()
 tractionModel.root.AssemblyLinearVelocity=vec(40,0,-30)
 local tractionController=VehiclePhysics.new(tractionModel)
 tractionController:step(1/60,0,0,false)
 return tractionModel.root.AssemblyLinearVelocity.X
end
local dry=lateralAfterStep(0)
local wet=lateralAfterStep(1)
assert(wet>dry,"Precipitation must reduce tyre grip")
rain=0
print("PASS: replicated precipitation reduces tyre grip")
Workspace.road=false
model.root.AssemblyLinearVelocity=vec(0,0,-30)
local speedBefore=model.root.AssemblyLinearVelocity.Magnitude
controller:step(1/60,1,1,false)
assert(model.attributes.GroundedWheels==0,"Airborne contacts must be absent")
assert(model.root.AssemblyLinearVelocity.Magnitude<speedBefore,"Airborne engine cannot generate traction")
print("PASS: no engine traction while airborne")
controller:destroy()
local after=model.root.AssemblyLinearVelocity
controller:step(1,1,1,true)
assert(model.root.AssemblyLinearVelocity==after,"Destroyed controller still applies forces")
print("PASS: destroyed controller is inert")
'''

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--luau', default=shutil.which('luau'))
    args = ap.parse_args()
    if not args.luau:
        ap.error('Pass --luau /path/to/the/official/luau/interpreter')
    source = (ROOT/'src/shared/VehiclePhysics.lua').read_text()
    harness = MOCKS+'\nlocal VehiclePhysics = (function()\n'+source+'\nend)()\n'+TESTS
    with tempfile.TemporaryDirectory(prefix='aster-vehicle-test-') as tmp:
        path = Path(tmp)/'vehicle_spec.luau'
        path.write_text(harness)
        subprocess.run([args.luau,str(path)],check=True)

if __name__ == '__main__':
    main()
