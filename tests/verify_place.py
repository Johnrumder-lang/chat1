#!/usr/bin/env python3
"""Validate the delivered XML, its complete car joint graph, and embedded sources."""
import argparse
import collections
import json
import math
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser()
parser.add_argument('--api-dump',type=Path,help='Optional Roblox API-Dump.json for current class/property checks')
args=parser.parse_args()
tree=ET.parse(ROOT/'dist/Northbound.rbxlx').getroot()
items=list(tree.iter('Item'))
refs={item.attrib['referent']:item for item in items}
assert len(refs)==len(items),'Duplicate referent'
def prop(item,name): return item.find(f"Properties/*[@name='{name}']")
def value(item,name):
    node=prop(item,name)
    return None if node is None else node.text
def name(item): return value(item,'Name')
def children(parent,cls): return [x for x in parent.iter('Item') if x.attrib['class']==cls]
def cf(node):
    return ([float(node.find(k).text) for k in ('X','Y','Z')],
            [float(node.find(f'R{r}{c}').text) for r in range(3) for c in range(3)])
def matmul(a,b): return [sum(a[r*3+k]*b[k*3+c] for k in range(3)) for r in range(3) for c in range(3)]
def compose(a,b):
    ap,ar=a;bp,br=b
    return ([ap[r]+sum(ar[r*3+k]*bp[k] for k in range(3)) for r in range(3)], matmul(ar,br))
checks=0
for item in items:
    properties=list(item.find('Properties'))
    assert len({x.attrib['name'] for x in properties})==len(properties),'Duplicate property'
    for node in properties:
        if node.tag=='Ref': assert node.text=='null' or node.text in refs, f'Dangling ref {node.text}'
        if node.tag=='CoordinateFrame':
            pos,rot=cf(node)
            assert all(math.isfinite(x) for x in pos+rot)
            for r in range(3):
                assert abs(sum(rot[r*3+k]**2 for k in range(3))-1)<1e-6,'Invalid CFrame basis'
    checks+=1
template=next(i for i in items if name(i)=='AsterTouring')
body=[i for i in template.iter('Item') if i.attrib['class'] in ('Part','WedgePart','VehicleSeat')]
spec=json.loads((ROOT/'assets/car.json').read_text())
assert len(body)==len(spec['parts'])
chassis=next(i for i in body if name(i)=='Chassis')
assert value(template,'PrimaryPart')==chassis.attrib['referent']
assert all(value(i,'Anchored')=='false' for i in body)
assert sum(value(i,'CanCollide')=='true' for i in body)==1
assert sum(value(i,'Massless')=='false' for i in body)==1
links=children(template,'Weld')+children(template,'Motor6D')
assert len(links)==len(body)-1,'Car must form a single tree of rigid joints'
parents={}
for joint in links:
    a,b=value(joint,'Part0'),value(joint,'Part1')
    assert b not in parents,'Part has multiple joints'
    assert a!=b,'Self joint'
    parents[b]=a
    # At rest both sides of every saved joint must coincide exactly.
    left=compose(cf(prop(refs[a],'CFrame')),cf(prop(joint,'C0')))
    right=compose(cf(prop(refs[b],'CFrame')),cf(prop(joint,'C1')))
    assert max(abs(a-b) for a,b in zip(left[0]+left[1],right[0]+right[1]))<1e-6, f'Bad rest frame {name(joint)} / {name(refs[b])}'
for part in body:
    current=part.attrib['referent'];seen=set()
    while current!=chassis.attrib['referent']:
        assert current not in seen,'Joint cycle'
        seen.add(current)
        assert current in parents,f'Unwelded car part {name(refs[current])}'
        current=parents[current]
assert len(children(template,'SpotLight'))==2
assert {name(i) for i in children(template,'Motor6D')}=={'WheelFL','WheelFR','WheelRL','WheelRR','WiperL','WiperR','Steering','Gauge1','Gauge2','Gauge3'}
rig=next(i for i in items if name(i)=='StarterCharacter')
assert value(children(rig,'Humanoid')[0],'RigType')=='0'
assert len(children(rig,'Motor6D'))==6
embedded=[value(i,'Source') for i in items if i.attrib['class'] in ('Script','LocalScript','ModuleScript')]
script_count=0
for folder in ('shared','server','client'):
    for source in (ROOT/'src'/folder).glob('*.lua'):
        expected=source.read_text()
        assert expected in embedded,f'Outdated source embedded: {source.name}'
        script_count+=1
assert script_count==8
assert 'rbxassetid://' not in (ROOT/'dist/Northbound.rbxlx').read_text(),'Unexpected uploaded asset dependency'
print(f'PASS: {len(items)} XML instances and all refs; 450-part connected car; joint rest frames; R6; headlights; {script_count} exact embedded scripts')

if args.api_dump:
    api=json.loads(args.api_dump.read_text());classes={x['Name']:x for x in api['Classes']};enums={x['Name']:x for x in api['Enums']}
    # These canonical XML aliases are documented by rojo-rbx/rbx-dom patches/parts.yml.
    aliases={'Color3uint8':'Color','size':'Size','shape':'Shape'}
    failures=set()
    for item in items:
        cls=item.attrib['class'];current=classes.get(cls);properties={}
        assert current, f'Unknown class: {cls}'
        while current:
            properties.update({m['Name']:m for m in current['Members'] if m['MemberType']=='Property'})
            current=classes.get(current['Superclass'])
        for node in item.find('Properties'):
            key=aliases.get(node.attrib['name'],node.attrib['name']);desc=properties.get(key)
            if not desc: failures.add(f'Unknown property: {cls}.{key}');continue
            if desc.get('Serialization',{}).get('CanLoad') is False: failures.add(f'Cannot load: {cls}.{key}')
            if desc['ValueType']['Category']=='Enum':
                values={x['Value'] for x in enums[desc['ValueType']['Name']]['Items']}
                if int(node.text) not in values: failures.add(f'Invalid enum: {cls}.{key}')
    assert not failures,'\n'.join(sorted(failures))
    print('PASS: current Roblox API classes, properties, loadability and enum values')
