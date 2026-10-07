"""Blender-only offline model study; this image is not Roblox gameplay.
Run: blender --background --python tools/preview_car.py
"""
import bpy
import json
import math
import sys
from pathlib import Path
from mathutils import Matrix, Vector
ROOT=Path(__file__).resolve().parents[1]
spec=json.loads((ROOT/'assets/car.json').read_text())
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
T=Matrix(((1,0,0,0),(0,0,-1,0),(0,1,0,0),(0,0,0,1)))
materials={}
def material(p):
 key=(tuple(p['color']),p['material'],p.get('transparency',0))
 if key in materials:return materials[key]
 m=bpy.data.materials.new(p['name']+' material');m.use_nodes=True
 nodes=m.node_tree.nodes;bsdf=nodes.get('Principled BSDF')
 rgb=[(v/255)**2.2 for v in p['color']]
 bsdf.inputs['Base Color'].default_value=(*rgb,1)
 bsdf.inputs['Metallic'].default_value=.55 if p['material']=='Metal' else .03
 bsdf.inputs['Roughness'].default_value=.30 if p['material']=='Metal' else .72 if p['material']=='Fabric' else .43
 if p['material']=='Neon':
  bsdf.inputs['Emission Color'].default_value=(*rgb,1);bsdf.inputs['Emission Strength'].default_value=1.8
 if p['material']=='Glass':
  bsdf.inputs['Roughness'].default_value=.14
  transparent=nodes.new('ShaderNodeBsdfTransparent')
  mix=nodes.new('ShaderNodeMixShader');mix.inputs[0].default_value=p.get('transparency',.6)
  m.node_tree.links.new(bsdf.outputs['BSDF'],mix.inputs[1]);m.node_tree.links.new(transparent.outputs[0],mix.inputs[2])
  m.node_tree.links.new(mix.outputs[0],nodes.get('Material Output').inputs['Surface'])
 materials[key]=m;return m
for p in spec['parts']:
 if p.get('transparency',0)>=1:continue
 sx,sy,sz=p['size']
 if p.get('shape')=='Cylinder':
  segments=40
  vertices=[(side*sx/2,math.cos(i*math.tau/segments)*sy/2,math.sin(i*math.tau/segments)*sz/2) for side in [-1,1] for i in range(segments)]
  faces=[tuple(range(segments-1,-1,-1)),tuple(range(segments,segments*2))]
  faces += [(i,(i+1)%segments,(i+1)%segments+segments,i+segments) for i in range(segments)]
  mesh=bpy.data.meshes.new(p['name']);mesh.from_pydata(vertices,[],faces);mesh.update()
  ob=bpy.data.objects.new(p['name'],mesh);bpy.context.collection.objects.link(ob)
 elif p.get('shape')=='Ball':
  bpy.ops.mesh.primitive_uv_sphere_add(segments=16,ring_count=8);ob=bpy.context.object
  for v in ob.data.vertices:v.co.x*=sx/2;v.co.y*=sy/2;v.co.z*=sz/2
 else:
  bpy.ops.mesh.primitive_cube_add(size=1);ob=bpy.context.object
  for v in ob.data.vertices:v.co.x*=sx;v.co.y*=sy;v.co.z*=sz
 ob.name=p['name']
 rx,ry,rz=[math.radians(v) for v in p.get('rotation',[0,0,0])]
 rotation=Matrix.Rotation(rx,4,'X')@Matrix.Rotation(ry,4,'Y')@Matrix.Rotation(rz,4,'Z')
 ob.matrix_world=T@rotation;ob.location=T.to_3x3()@Vector(p['position'])
 ob.data.materials.append(material(p))
 # A restrained edge highlight makes the original geometry readable.
 if p.get('shape','Block')=='Block' and min(p['size'])>.11:
  bevel=ob.modifiers.new('Tiny manufactured edge','BEVEL');bevel.width=min(.045,min(p['size'])*.16);bevel.segments=2
  ob.modifiers.new('Weighted corner normals','WEIGHTED_NORMAL')
bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-2.025))
floor=bpy.context.object;floor.name='Neutral model-study floor'
m=bpy.data.materials.new('Studio slate');m.diffuse_color=(.105,.135,.128,1);floor.data.materials.append(m)
world=bpy.context.scene.world;world.use_nodes=True;world.node_tree.nodes['Background'].inputs[0].default_value=(.34,.41,.45,1);world.node_tree.nodes['Background'].inputs[1].default_value=.55
for name,pos,power,size in [('Key',(-7,7,15),2100,10),('Rim',(9,-7,11),2000,8),('Soft front',(-10,-5,6),1300,7)]:
 light=bpy.data.lights.new(name,'AREA');light.energy=power;light.shape='DISK';light.size=size
 ob=bpy.data.objects.new(name,light);bpy.context.collection.objects.link(ob);ob.location=pos;ob.rotation_euler=(Vector((0,0,1))-ob.location).to_track_quat('-Z','Y').to_euler()
camdata=bpy.data.cameras.new('Model study camera');cam=bpy.data.objects.new('Model study camera',camdata);bpy.context.collection.objects.link(cam)
cam.location=(-16,22,11);target=Vector((0,.0,1.2));cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();camdata.type='ORTHO';camdata.ortho_scale=21.3
scene=bpy.context.scene;scene.camera=cam;scene.render.engine='CYCLES';scene.cycles.samples=48;scene.cycles.use_denoising=False
scene.render.resolution_x=1100;scene.render.resolution_y=760;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG';scene.render.filepath=str(ROOT/'dist/car-model-preview.png')
scene.view_settings.view_transform='AgX';scene.render.film_transparent=False
if '--interior' in sys.argv:
 cam.location=T.to_3x3()@Vector(spec['cameraPosition'])
 target=cam.location+Vector((0,20,0))
 cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler()
 camdata.type='PERSP';camdata.lens=24;camdata.clip_start=.025
 scene.render.filepath=str(ROOT/'dist/cockpit-model-preview.png')
 scene.render.resolution_x=960;scene.render.resolution_y=640
 scene.cycles.samples=24
bpy.ops.render.render(write_still=True)
