import subprocess,time,json,pathlib,os
root=pathlib.Path('/workspace')
app=root/'dart_simple_live/simple_live_app'
dart=str(root/'flutter/bin/cache/dart-sdk/bin/dart')
tool=str(root/'flutter/bin/cache/flutter_tools.snapshot')
os.environ["PROGRAMFILES(X86)"]="/workspace/empty-program-files"
os.environ["XDG_RUNTIME_DIR"]="/workspace/wine-runtime"
pathlib.Path("/workspace/wine-runtime").mkdir(mode=0o700,exist_ok=True)
results={}
for target,name in [('lib/main.dart','remote_release'),('lib/testing/mini_player_probe.dart','remote_probe')]:
 start=time.monotonic()
 command=[dart,tool,'assemble','--output=build/'+name,'-dTargetPlatform=windows-x64','-dBuildMode=release','-dTargetFile='+target,'release_bundle_windows-x64_assets']
 with (root/'logs'/f'{name}.log').open('w') as log:
  run=subprocess.run(command,cwd=app,stdout=log,stderr=subprocess.STDOUT)
 results[name]={'exitCode':run.returncode,'seconds':round(time.monotonic()-start,2)}
 (root/'logs/compile-results.json').write_text(json.dumps(results,indent=2))
 if run.returncode: raise SystemExit(run.returncode)
