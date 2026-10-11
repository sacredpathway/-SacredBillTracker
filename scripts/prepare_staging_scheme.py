"""Generate a temporary, non-archivable staging launch/test scheme; never store private credentials."""
import os, json, base64
from pathlib import Path
import xml.etree.ElementTree as ET
key=os.environ.get('SBT_STAGING_PUBLIC_KEY','')
try:
 claims=json.loads(base64.urlsafe_b64decode(key.split('.')[1]+'==='))
 assert claims['ref']=='thwjnpofhrpxfuvwkfgd' and claims['role']=='anon'
except Exception: raise SystemExit('Missing or wrong-project staging anon configuration')
p=Path('SacredBillTracker.xcodeproj/xcshareddata/xcschemes/SacredBillTracker.xcscheme')
t=ET.parse(p);root=t.getroot()
for node in root.findall('.//BuildActionEntry'):node.set('buildForArchiving','NO');node.set('buildForProfiling','NO')
for tag in ['ArchiveAction','ProfileAction']:
 for node in root.findall(tag):root.remove(node)
launch=root.find('LaunchAction')
for node in launch.findall('StoreKitConfigurationFileReference'):launch.remove(node)
env=ET.SubElement(launch,'EnvironmentVariables')
for name,value in {'SBT_STAGING_PROJECT':'thwjnpofhrpxfuvwkfgd','SBT_STAGING_URL':'https://thwjnpofhrpxfuvwkfgd.supabase.co','SBT_STAGING_PUBLIC_KEY':key}.items():
 ET.SubElement(env,'EnvironmentVariable',{'key':name,'value':value,'isEnabled':'YES'})
for label in ['A','B']:
 name='SBT_ROUTING_ACCOUNT_'+label+'_TOKEN'
 if os.environ.get(name):ET.SubElement(env,'EnvironmentVariable',{'key':name,'value':os.environ[name],'isEnabled':'YES'})
p=p.with_name('SacredBillTracker-Staging.xcscheme');t.write(p,encoding='UTF-8',xml_declaration=True)
os.chmod(p,0o600)
print('Prepared STAGING scheme: isolated project; archive/profile actions absent; local StoreKit config absent')
