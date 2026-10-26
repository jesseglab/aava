import pathlib,plistlib,shutil,subprocess
root=pathlib.Path(__file__).resolve().parents[1]
app=root/'build/mac/Aava.app';contents=app/'Contents'
base={'CFBundleDevelopmentRegion':'en','CFBundleInfoDictionaryVersion':'6.0','CFBundlePackageType':'APPL','CFBundleVersion':'3','CFBundleShortVersionString':'0.3.0','LSMinimumSystemVersion':'14.0','NSSupportsAutomaticGraphicsSwitching':True,'LSFileQuarantineEnabled':True,'LSEnvironment':{'MallocNanoZone':'0'}}
info={**base,'CFBundleName':'Aava','CFBundleDisplayName':'Aava','CFBundleExecutable':'Aava','CFBundleIconFile':'AppIcon','CFBundleIdentifier':'app.geeklab.aava.dev','NSPrincipalClass':'AavaApplication','NSHighResolutionCapable':True,'NSCameraUsageDescription':'Allow websites you approve to use your camera for calls.','NSMicrophoneUsageDescription':'Allow websites you approve to use your microphone for calls.','CFBundleURLTypes':[{'CFBundleURLName':'Web addresses','CFBundleTypeRole':'Viewer','CFBundleURLSchemes':['http','https']}],'CFBundleDocumentTypes':[{'CFBundleTypeName':'Web page','CFBundleTypeRole':'Viewer','LSHandlerRank':'Alternate','LSItemContentTypes':['public.html','public.xhtml']}],'NSUserActivityTypes':['NSUserActivityTypeBrowsingWeb']}
(contents/'Info.plist').write_bytes(plistlib.dumps(info))
framework=contents/'Frameworks/Chromium Embedded Framework.framework'
dest=framework/'Versions/A'
if not dest.exists():
 dest.parent.mkdir(parents=True,exist_ok=True)
 subprocess.run(['ditto',str(root/'vendor/cef/Release/Chromium Embedded Framework.framework'),str(dest)],check=True)
for name,target in [('Chromium Embedded Framework','Versions/A/Chromium Embedded Framework'),('Libraries','Versions/A/Libraries'),('Resources','Versions/A/Resources'),('Versions/Current','A')]:
 link=framework/name
 if not link.is_symlink():link.symlink_to(target)
for suffix,bundle_suffix in [('', ''),(' (Alerts)','.alerts'),(' (GPU)','.gpu'),(' (Plugin)','.plugin'),(' (Renderer)','.renderer')]:
 name='Aava Helper'+suffix
 helper=contents/'Frameworks'/f'{name}.app'/'Contents'
 (helper/'MacOS').mkdir(parents=True,exist_ok=True)
 shutil.copy2(root/'build/mac/AavaHelper',helper/'MacOS'/name)
 data={**base,'CFBundleName':name,'CFBundleExecutable':name,'CFBundleIdentifier':'app.geeklab.aava.dev.helper'+bundle_suffix,'LSUIElement':True}
 (helper/'Info.plist').write_bytes(plistlib.dumps(data))
for name in ['LICENSE.txt','CREDITS.html']:
 shutil.copy2(root/'vendor/cef'/name,contents/'Resources'/name)
icons=root/'Apps/macOS/Resources/Icons'
if icons.exists():shutil.copytree(icons,contents/'Resources/Icons',dirs_exist_ok=True)
for name in ['heroicons-license.txt','lucide-license.txt']:
 shutil.copy2(root/'Apps/macOS/Resources'/name,contents/'Resources'/name)

brand=root/'Apps/macOS/Resources/Brand'
shutil.copytree(brand,contents/'Resources/Brand',dirs_exist_ok=True)
shutil.copy2(brand/'AppIcon.icns',contents/'Resources/AppIcon.icns')
shutil.copy2(root/'scripts/aava-mini.py',contents/'Resources/aava-mini.py')
