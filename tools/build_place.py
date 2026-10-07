#!/usr/bin/env python3
"""Build a self-contained Roblox XML place using only Python's standard library."""
from __future__ import annotations
import json
import math
import pathlib
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / 'dist' / 'Northbound.rbxlx'


class Place:
    def __init__(self):
        self.xml = ET.Element('roblox', {'xmlns:xmime': 'http://www.w3.org/2005/05/xmlmime', 'version': '4'})
        ET.SubElement(self.xml, 'External').text = 'null'
        ET.SubElement(self.xml, 'External').text = 'nil'
        self.count = 0

    def item(self, parent, cls, name):
        self.count += 1
        node = ET.SubElement(parent, 'Item', {'class': cls, 'referent': f'RBX{self.count:08d}'})
        ET.SubElement(node, 'Properties')
        self.prop(node, 'string', 'Name', name)
        return node

    def prop(self, node, kind, name, value):
        props = node.find('Properties')
        for old in list(props):
            if old.get('name') == name:
                props.remove(old)
        el = ET.SubElement(props, kind, {'name': name})
        if kind in ('Vector3', 'Color3'):
            for axis, num in zip(('X', 'Y', 'Z') if kind == 'Vector3' else ('R', 'G', 'B'), value):
                ET.SubElement(el, axis).text = f'{num:.9g}'
        elif kind == 'CoordinateFrame':
            pos, rot = value
            for axis, num in zip(('X', 'Y', 'Z'), pos):
                ET.SubElement(el, axis).text = f'{num:.9g}'
            for i, num in enumerate(rot):
                ET.SubElement(el, f'R{i//3}{i%3}').text = f'{num:.9g}'
        elif kind == 'Ref':
            el.text = value.get('referent') if value is not None else 'null'
        elif kind == 'bool':
            el.text = str(bool(value)).lower()
        elif kind == 'Content':
            ET.SubElement(el, 'url').text = str(value)
        else:
            el.text = str(value)
        return el

    def color(self, node, name, rgb):
        return self.prop(node, 'Color3', name, [c / 255 for c in rgb])

    def part(self, parent, name, size, pos, color, *, rotation=(0, 0, 0), cls='Part', anchored=True, collide=False, material='SmoothPlastic', transparency=0, shape='Block'):
        part = self.item(parent, cls, name)
        self.prop(part, 'Vector3', 'size', size)
        self.prop(part, 'CoordinateFrame', 'CFrame', (pos, matrix(rotation)))
        self.prop(part, 'Color3uint8', 'Color3uint8', 0xFF000000 | (color[0] << 16) | (color[1] << 8) | color[2])
        self.prop(part, 'bool', 'Anchored', anchored)
        self.prop(part, 'bool', 'CanCollide', collide)
        self.prop(part, 'bool', 'CanTouch', collide)
        self.prop(part, 'bool', 'CanQuery', collide)
        self.prop(part, 'bool', 'Massless', not collide)
        self.prop(part, 'float', 'Transparency', transparency)
        self.prop(part, 'token', 'Material', MATERIALS[material])
        self.prop(part, 'token', 'TopSurface', 0)
        self.prop(part, 'token', 'BottomSurface', 0)
        if cls == 'Part':
            self.prop(part, 'token', 'shape', {'Ball': 0, 'Block': 1, 'Cylinder': 2}[shape])
        return part


MATERIALS = {'Plastic': 256, 'SmoothPlastic': 272, 'Neon': 288, 'Wood': 512, 'WoodPlanks': 528, 'Marble': 784, 'Slate': 800, 'Concrete': 816, 'Granite': 832, 'Brick': 848, 'Pebble': 864, 'Cobblestone': 880, 'Rock': 896, 'Sandstone': 912, 'Basalt': 788, 'CrackedLava': 804, 'Limestone': 820, 'Pavement': 836, 'CorrodedMetal': 1040, 'DiamondPlate': 1056, 'Foil': 1072, 'Metal': 1088, 'Grass': 1280, 'Sand': 1296, 'Fabric': 1312, 'Snow': 1328, 'Mud': 1344, 'Ground': 1360, 'Asphalt': 1376, 'LeafyGrass': 1284, 'Salt': 1392, 'Ice': 1536, 'Glacier': 1552, 'Glass': 1568, 'ForceField': 1584, 'Water': 2048}


def matrix(degrees):
    x, y, z = [math.radians(v) for v in degrees]
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    return (cy*cz, -cy*sz, sy, cx*sz+sx*sy*cz, cx*cz-sx*sy*sz, -sx*cy, sx*sz-cx*sy*cz, sx*cz+cx*sy*sz, cx*cy)


IDENTITY = matrix((0, 0, 0))


def relative_frame(parent_desc, child_desc):
    """Roblox parent:ToObjectSpace(child), kept explicit for portable saved joints."""
    parent_r=matrix(parent_desc.get('rotation',(0,0,0)))
    child_r=matrix(child_desc.get('rotation',(0,0,0)))
    inverse=tuple(parent_r[col*3+row] for row in range(3) for col in range(3))
    delta=[child_desc['position'][i]-parent_desc['position'][i] for i in range(3)]
    pos=[sum(inverse[row*3+k]*delta[k] for k in range(3)) for row in range(3)]
    rot=tuple(sum(inverse[row*3+k]*child_r[k*3+col] for k in range(3)) for row in range(3) for col in range(3))
    return pos,rot


def car_model(p, parent, spec, name='AsterTouring', preview=False, offset=(0, 0, 0)):
    model = p.item(parent, 'Model', name)
    p.prop(model, 'token', 'ModelStreamingMode', 2)
    parts = {}
    indexed_parts = []
    group_roots = {}
    descriptions = {d['name']:d for d in spec['parts']}
    for desc in spec['parts']:
        pos = [v + offset[i] for i, v in enumerate(desc['position'])]
        part = p.part(model, desc['name'], desc['size'], pos, desc['color'], rotation=desc.get('rotation', (0,0,0)), cls=desc.get('class', 'Part'), anchored=preview, collide=desc.get('collide', desc['name'] == 'Chassis'), material=desc.get('material','SmoothPlastic'), transparency=desc.get('transparency',0), shape=desc.get('shape','Block'))
        parts[desc['name']] = part
        indexed_parts.append(part)
        group = desc.get('group', 'Body')
        if desc['name'] == group:
            group_roots[group] = part
        if desc.get('reflectance') is not None:
            p.prop(part, 'float', 'Reflectance', desc['reflectance'])
        if desc['name'] == 'DriverSeat':
            p.prop(part, 'bool', 'HeadsUpDisplay', False)
            p.prop(part, 'float', 'MaxSpeed', 0)
            p.prop(part, 'float', 'Torque', 0)
            p.prop(part, 'float', 'TurnSpeed', 0)
        if desc['name'].startswith('Roof') or desc['name'] == 'Windscreen':
            p.prop(part, 'bool', 'CanQuery', True)
        if desc.get('light') == 'headlight':
            light = p.item(part, 'SpotLight', 'RoadLamp')
            p.prop(light, 'bool', 'Enabled', True)
            p.prop(light, 'float', 'Brightness', 3)
            p.prop(light, 'float', 'Range', 60)
            p.prop(light, 'float', 'Angle', 78)
            p.prop(light, 'token', 'Face', 5)
            p.prop(light, 'bool', 'Shadows', True)
            p.color(light, 'Color', (255,231,190))
        if desc.get('label'):
            gui=p.item(part,'SurfaceGui','Engraving')
            p.prop(gui,'token','Face',5 if 'Front' in desc['name'] else 2)
            p.prop(gui,'float','PixelsPerStud',120)
            p.prop(gui,'token','SizingMode',1)
            p.prop(gui,'bool','AlwaysOnTop',False)
            label=p.item(gui,'TextLabel','Label')
            p.prop(label,'string','Text',desc['label'])
            p.prop(label,'float','BackgroundTransparency',1)
            p.prop(label,'bool','TextScaled',True)
            p.prop(label,'token','Font',19)
            p.color(label,'TextColor3',(35,42,37))
            size=ET.SubElement(label.find('Properties'),'UDim2',{'name':'Size'})
            for key,val in [('XS',1),('XO',0),('YS',1),('YO',0)]: ET.SubElement(size,key).text=str(val)
    chassis = parts['Chassis']
    p.prop(model, 'Ref', 'PrimaryPart', chassis)
    needle_index=0
    for desc,part in zip(spec['parts'],indexed_parts):
        if part is chassis:
            continue
        group = desc.get('group','Body')
        if desc['name'] in ('WiperLeft','WiperRight'):
            joint=p.item(chassis,'Motor6D','WiperL' if desc['name']=='WiperLeft' else 'WiperR')
            p.prop(joint,'Ref','Part0',chassis); p.prop(joint,'Ref','Part1',part)
            # C0*C1^-1 equals the authored part frame; rotation happens about its spindle.
            pivot=spec['wiperPivots'][desc['name']]
            pivot_desc={'position':pivot,'rotation':(36,0,0)}
            p.prop(joint,'CoordinateFrame','C0',(pivot,matrix((36,0,0))))
            p.prop(joint,'CoordinateFrame','C1',relative_frame(desc,pivot_desc))
        elif desc['name']=='GaugeNeedle':
            needle_index+=1
            joint=p.item(chassis,'Motor6D',f'Gauge{needle_index}')
            p.prop(joint,'Ref','Part0',chassis); p.prop(joint,'Ref','Part1',part)
            p.prop(joint,'CoordinateFrame','C0',(desc['position'],matrix(desc.get('rotation',(0,0,0)))))
            p.prop(joint,'CoordinateFrame','C1',((0,0,0),IDENTITY))
        elif desc['name']=='SteeringHub':
            joint=p.item(chassis,'Motor6D','Steering')
            p.prop(joint,'Ref','Part0',chassis); p.prop(joint,'Ref','Part1',part)
            p.prop(joint,'CoordinateFrame','C0',(desc['position'],matrix(desc.get('rotation',(0,0,0)))))
            p.prop(joint,'CoordinateFrame','C1',((0,0,0),IDENTITY))
        elif group != 'Body' and desc['name'] == group:
            joint = p.item(chassis, 'Motor6D', group)
            p.prop(joint, 'Ref', 'Part0', chassis)
            p.prop(joint, 'Ref', 'Part1', part)
            pivot = spec.get('pivots',{}).get(group, desc['position'])
            p.prop(joint,'CoordinateFrame','C0',(pivot, IDENTITY))
            delta = [pivot[i]-desc['position'][i] for i in range(3)]
            p.prop(joint,'CoordinateFrame','C1',(delta, IDENTITY))
        else:
            joint = p.item(part, 'Weld', 'AssemblyWeld')
            parent_root = parts['SteeringHub'] if desc['name'] in ('SteeringRim','SteeringSpoke') else group_roots.get(group,chassis)
            p.prop(joint, 'Ref', 'Part0', parent_root)
            p.prop(joint, 'Ref', 'Part1', part)
            parent_name=parent_root.find("Properties/string[@name='Name']").text
            p.prop(joint,'CoordinateFrame','C0',relative_frame(descriptions[parent_name],desc))
            p.prop(joint,'CoordinateFrame','C1',((0,0,0),IDENTITY))
    attachment = p.item(chassis,'Attachment','DriverEye')
    p.prop(attachment,'CoordinateFrame','CFrame',(spec.get('cameraPosition',[-1.42,2.8,0.35]),IDENTITY))
    return model


def r6_character(p, starter):
    model = p.item(starter,'Model','StarterCharacter')
    defs = [('HumanoidRootPart',(2,2,1),(0,5,0),(80,87,80)),('Torso',(2,2,1),(0,5,0),(64,80,76)),('Head',(2,1,1),(0,6.5,0),(214,179,145)),('Left Arm',(1,2,1),(-1.5,5,0),(64,80,76)),('Right Arm',(1,2,1),(1.5,5,0),(64,80,76)),('Left Leg',(1,2,1),(-.5,3,0),(48,52,52)),('Right Leg',(1,2,1),(.5,3,0),(48,52,52))]
    parts = {name:p.part(model,name,size,pos,color,anchored=False,collide=name=='Torso',transparency=1 if name=='HumanoidRootPart' else 0) for name,size,pos,color in defs}
    p.prop(parts['HumanoidRootPart'],'bool','Massless',False)
    p.prop(model,'Ref','PrimaryPart',parts['HumanoidRootPart'])
    humanoid = p.item(model,'Humanoid','Humanoid')
    p.prop(humanoid,'token','RigType',0)
    p.prop(humanoid,'float','WalkSpeed',16)
    p.prop(humanoid,'float','HipHeight',0)
    p.prop(humanoid,'float','MaxHealth',100)
    p.prop(humanoid,'float','Health',100)
    for name,a,b,c0,c1 in [
        ('RootJoint','HumanoidRootPart','Torso',(0,0,0),(0,0,0)),
        ('Neck','Torso','Head',(0,1,0),(0,-.5,0)),
        ('Left Shoulder','Torso','Left Arm',(-1,.5,0),(.5,.5,0)),
        ('Right Shoulder','Torso','Right Arm',(1,.5,0),(-.5,.5,0)),
        ('Left Hip','Torso','Left Leg',(-.5,-1,0),(0,1,0)),
        ('Right Hip','Torso','Right Leg',(.5,-1,0),(0,1,0)),
    ]:
        joint=p.item(parts[a],'Motor6D',name)
        p.prop(joint,'Ref','Part0',parts[a]); p.prop(joint,'Ref','Part1',parts[b])
        p.prop(joint,'CoordinateFrame','C0',(c0,IDENTITY)); p.prop(joint,'CoordinateFrame','C1',(c1,IDENTITY))
    headmesh=p.item(parts['Head'],'SpecialMesh','HeadMesh')
    p.prop(headmesh,'token','MeshType',0)
    p.prop(headmesh,'Vector3','Scale',(1.25,1.25,1.25))
    return model


def editor_preview(p, world, spec):
    """A visible opening scene in edit mode. Replaced by smooth generated Terrain in Play."""
    scene=p.item(world,'Model','EditorPreview')
    p.part(scene,'AlpineMeadow',(700,10,900),(0,23,0),(87,106,70),material='Grass',collide=True)
    p.part(scene,'Road',(30,1,900),(0,32,0),(62,65,65),material='Asphalt',collide=True)
    for z in range(-440,441,32):
        p.part(scene,'CentreMark',(.22,.05,13),(0,32.53,z),(222,203,149))
    for x in (-14,14): p.part(scene,'EdgeMark',(.2,.06,900),(x,32.54,0),(218,219,203))
    for i in range(30):
        side=-1 if i%2 else 1
        x=side*(55+(i*37)%170); z=-420+(i*67)%800
        height=24+i%5*3
        p.part(scene,'PineTrunk',(2,height*.55,2),(x,28+height*.22,z),(83,70,53),material='Wood')
        for j in range(4):
            # Overlapping tapered wedge pairs make an asset-free editor silhouette.
            width=(height*.7)*(1-j*.19)
            for yaw in (0,180):
                p.part(scene,'FirCrown',(width,height*.4,width/2),(x,33+j*height*.17,z),(44+j*3,67+j*4,55+j*2),cls='WedgePart',rotation=(0,yaw,0),material='Grass')
    for side in (-1,1):
        for i in range(6):
            p.part(scene,'Mountain',(200,180+i%3*60,320),(side*(360+i%2*90),55,-700+i*260),(97+i*4,106+i*3,103+i*3),cls='WedgePart',rotation=(0,90 if side==1 else -90,0),material='Slate')
    car_model(p,scene,spec,'Aster · Touring',preview=True,offset=(-7,34.6,0))
    camera=p.item(world,'Camera','Camera')
    # Studio's initial camera looks toward the preview car from the front quarter.
    pos=(-27,45,-30); target=(-5,35,2)
    look=[target[i]-pos[i] for i in range(3)]
    ln=math.sqrt(sum(x*x for x in look)); look=[x/ln for x in look]
    right=[-look[2],0,look[0]]; rn=math.sqrt(sum(x*x for x in right)); right=[x/rn for x in right]
    back=[-x for x in look]; up=[back[1]*right[2]-back[2]*right[1],back[2]*right[0]-back[0]*right[2],back[0]*right[1]-back[1]*right[0]]
    rot=tuple(v for row in zip(right,up,back) for v in row)
    p.prop(camera,'CoordinateFrame','CFrame',(pos,rot)); p.prop(world,'Ref','CurrentCamera',camera)


def main():
    p=Place()
    workspace=p.item(p.xml,'Workspace','Workspace')
    p.prop(workspace,'float','Gravity',196.2)
    p.prop(workspace,'float','FallenPartsDestroyHeight',-500)
    p.prop(workspace,'bool','StreamingEnabled',True)
    p.prop(workspace,'int','StreamingMinRadius',256)
    p.prop(workspace,'int','StreamingTargetRadius',1500)
    terrain=p.item(workspace,'Terrain','Terrain')
    p.color(terrain,'WaterColor',(48,89,93)); p.prop(terrain,'float','WaterTransparency',.28)
    p.prop(terrain,'float','WaterReflectance',.55); p.prop(terrain,'float','WaterWaveSize',.18); p.prop(terrain,'float','WaterWaveSpeed',8)
    p.item(workspace,'Folder','Vehicles'); p.item(workspace,'Folder','Scenery')
    lighting=p.item(p.xml,'Lighting','Lighting')
    p.prop(lighting,'token','Technology',4) # Future lighting; Studio may migrate to Unified lighting.
    p.prop(lighting,'bool','GlobalShadows',True)
    p.prop(lighting,'float','ClockTime',16.35); p.prop(lighting,'float','Brightness',2.6)
    p.prop(lighting,'float','EnvironmentDiffuseScale',.7); p.prop(lighting,'float','EnvironmentSpecularScale',1)
    p.prop(lighting,'float','ShadowSoftness',.3)
    p.color(lighting,'Ambient',(62,69,75)); p.color(lighting,'OutdoorAmbient',(112,119,119))
    p.prop(lighting,'float','GeographicLatitude',42)
    sky=p.item(lighting,'Sky','AlpineSky')
    for key,suffix in [('SkyboxBk','bk'),('SkyboxDn','dn'),('SkyboxFt','ft'),('SkyboxLf','lf'),('SkyboxRt','rt'),('SkyboxUp','up')]:
        p.prop(sky,'Content',key,f'rbxasset://textures/sky/sky512_{suffix}.tex')
    p.prop(sky,'int','StarCount',1500)
    atmosphere=p.item(lighting,'Atmosphere','RoadTripAtmosphere')
    p.prop(atmosphere,'float','Density',.28); p.prop(atmosphere,'float','Haze',1.5)
    p.color(atmosphere,'Color',(204,215,218)); p.color(atmosphere,'Decay',(132,157,162))
    replicated=p.item(p.xml,'ReplicatedStorage','ReplicatedStorage')
    shared=p.item(replicated,'Folder','RoadTrip'); p.item(shared,'RemoteEvent','Action')
    storage=p.item(p.xml,'ServerStorage','ServerStorage')
    server=p.item(p.xml,'ServerScriptService','ServerScriptService')
    serverfolder=p.item(server,'Folder','RoadTripServer')
    starter=p.item(p.xml,'StarterPlayer','StarterPlayer')
    p.prop(starter,'float','CameraMinZoomDistance',.5); p.prop(starter,'float','CameraMaxZoomDistance',.5)
    p.prop(starter,'bool','EnableMouseLockOption',False)
    client=p.item(starter,'StarterPlayerScripts','StarterPlayerScripts')
    clientfolder=p.item(client,'Folder','RoadTripClient')
    r6_character(p,starter)
    p.item(p.xml,'StarterGui','StarterGui')
    sound=p.item(p.xml,'SoundService','SoundService'); p.prop(sound,'bool','RespectFilteringEnabled',True)
    spawn=p.part(workspace,'SpawnLocation',(6,1,6),(-27,34,8),(100,110,95),cls='SpawnLocation',collide=True,transparency=1)
    p.prop(spawn,'bool','Neutral',True); p.prop(spawn,'int','Duration',0)
    spec=json.loads((ROOT/'assets/car.json').read_text())
    car_model(p,storage,spec)
    editor_preview(p,workspace,spec)
    scripts=[]
    for area,parent in [('shared',shared),('server',serverfolder),('client',clientfolder)]:
        for path in sorted((ROOT/'src'/area).glob('*.lua')):
            name=path.name.removesuffix('.lua')
            cls='ModuleScript'
            if name.endswith('.server'): name=name.removesuffix('.server'); cls='Script'
            if name.endswith('.client'): name=name.removesuffix('.client'); cls='LocalScript'
            script=p.item(parent,cls,name)
            p.prop(script,'ProtectedString','Source',path.read_text())
            if cls!='ModuleScript': p.prop(script,'bool','Disabled',False)
            scripts.append(str(path.relative_to(ROOT)))
    OUT.parent.mkdir(parents=True,exist_ok=True)
    ET.indent(p.xml,space='  ')
    ET.ElementTree(p.xml).write(OUT,encoding='utf-8',xml_declaration=True)
    print(f'Built {OUT.name}: {p.count} instances, {len(scripts)} scripts, {OUT.stat().st_size:,} bytes')
    (ROOT/'dist/manifest.json').write_text(json.dumps({'place':OUT.name,'instances':p.count,'scripts':scripts,'carParts':len(spec['parts']),'externalAssetIds':[]},indent=2)+'\n')


if __name__=='__main__': main()
