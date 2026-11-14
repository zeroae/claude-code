#!/usr/bin/env bash
# Usage: scripts/smoke-test-image.sh <claude|codex|t3> <image>
set -euo pipefail
image_target=${1:?Expected image target}
image_ref=${2:?Expected image reference}
case "$image_target" in claude|codex|t3) ;; *) echo "Unknown target: $image_target" >&2; exit 1 ;; esac

docker run --rm -i --tmpfs /root/.codex --tmpfs /root/.t3 \
  --entrypoint sh "$image_ref" -s -- "$image_target" <<'CHECKS'
set -eu
node - "$1" <<'VERSIONS'
const fs=require('fs'),cp=require('child_process');
const versions=JSON.parse(fs.readFileSync('/opt/image-versions.json','utf8'));
const target=process.argv[2];
for(const tool of target==='t3'?['claude','codex','t3']:[target]){
  const output=cp.execFileSync(tool,['--version'],{encoding:'utf8'}).trim();
  const actual=tool==='claude'?output.split(/\s+/)[0]:output.split(/\s+/).pop().replace(/^v/,'');
  if(versions[tool]!==actual)throw Error(`${tool} metadata ${versions[tool]} differs from installed ${actual}`);
}
console.log('Installed versions:',JSON.stringify(versions));
VERSIONS
verify_windows_exe() {
  test -s "$1"
  file "$1" | tee /tmp/windows-file-type
  grep -q "${2:-PE32+.*x86-64}" /tmp/windows-file-type
}
verify_codex_vsix() {
  unzip -tq "$1"
  node - "$1" "$2" <<'VSIX'
const fs=require('fs'),cp=require('child_process');
const [archive,platform]=process.argv.slice(2);
const extension=JSON.parse(cp.execFileSync('unzip',['-p',archive,'extension/package.json'],{encoding:'utf8'}));
const manifest=cp.execFileSync('unzip',['-p',archive,'extension.vsixmanifest'],{encoding:'utf8'});
const versions=JSON.parse(fs.readFileSync('/opt/image-versions.json','utf8'));
if(extension.publisher!=='openai'||extension.name!=='chatgpt'||extension.version!==versions.codex_vsix||!manifest.includes(`TargetPlatform="${platform}"`))throw Error(`Invalid Codex VSIX: ${archive}`);
console.log('Codex VSIX:',platform,extension.version);
VSIX
}
if [ "$1" = codex ] || [ "$1" = t3 ]; then
  verify_windows_exe /opt/codex/win32-x64/bin/codex.exe
  verify_codex_vsix /opt/codex/win32-x64/codex.vsix win32-x64
  node <<'CODEX_WINDOWS'
const fs=require('fs');
const versions=JSON.parse(fs.readFileSync('/opt/image-versions.json','utf8'));
const windows=JSON.parse(fs.readFileSync('/opt/codex/win32-x64/codex-package.json','utf8'));
if(windows.version!==versions.codex||windows.target!=='x86_64-pc-windows-msvc')throw Error('Invalid Windows Codex package');
CODEX_WINDOWS
fi
if [ "$1" = t3 ]; then
  verify_windows_exe /opt/claude-code/win32-x64/claude.exe
  # The x64 NSIS installer uses a 32-bit bootstrap executable. Its payload is
  # selected and checksum-verified against the release's x64 metadata at build.
  verify_windows_exe /opt/t3-code/win32-x64/T3-Code-Setup.exe 'PE32.*Nullsoft Installer'
  node <<'WINDOWS'
const fs=require('fs'),path=require('path'),cp=require('child_process');
const base='/opt/t3-code/win32-x64';
const executables=fs.readdirSync(base,{recursive:true}).filter(p=>path.basename(p)==='t3.exe');
if(executables.length!==1)throw Error('Expected one Windows T3 server executable');
const binary=path.join(base,executables[0]);
const type=cp.execFileSync('file',[binary],{encoding:'utf8'});
if(!/PE32\+.*x86-64/.test(type))throw Error(type);
if(!fs.existsSync(path.join(path.dirname(binary),'client','index.html')))throw Error('Missing Windows server web UI');
console.log(type.trim());
console.log('Windows T3 server web UI present');
WINDOWS
fi
case "$1" in
  claude)
    claude --version
    if command -v codex; then echo "Unexpected Codex CLI" >&2; exit 1; fi
    if command -v t3; then echo "Unexpected T3 CLI" >&2; exit 1; fi
    ;;
  codex)
    codex --version
    if command -v claude; then echo "Unexpected Claude CLI" >&2; exit 1; fi
    if command -v t3; then echo "Unexpected T3 CLI" >&2; exit 1; fi
    case "$(uname -m)" in aarch64) platform=linux-arm64 ;; x86_64) platform=linux-x64 ;; esac
    verify_codex_vsix /opt/codex/codex.vsix "$platform"
    ;;
  t3)
    claude --version
    codex --version
    t3 --version
    test -x /usr/local/bin/t3-desktop
    test -s /opt/t3-desktop/resources/app.asar
    ldd /opt/t3-desktop/t3code > /tmp/desktop-libs
    if grep 'not found' /tmp/desktop-libs; then exit 1; fi
    ELECTRON_RUN_AS_NODE=1 /opt/t3-desktop/t3code -e 'console.log("Desktop Electron:",process.versions.electron)'
    t3 serve --host 0.0.0.0 --port 3773 > /tmp/t3.log 2>&1 &
    server_pid=$!
    trap 'kill "$server_pid" 2>/dev/null || true' EXIT
    attempt=0
    until curl -fsS http://127.0.0.1:3773/ -o /tmp/index.html 2>/dev/null; do
      attempt=$((attempt + 1))
      if [ "$attempt" -ge 20 ]; then cat /tmp/t3.log; exit 1; fi
      sleep 1
    done
    node <<'JS'
const fs=require('fs'),cp=require('child_process');
const html=fs.readFileSync('/tmp/index.html','utf8');
if(!html.toLowerCase().includes('<!doctype html>'))throw Error('Missing UI HTML');
const assets=[...html.matchAll(/(?:src|href)="([^" ]+\.(?:js|css))"/g)].map(m=>m[1]);
if(!assets.length)throw Error('Missing UI assets');
for(const asset of assets){
  const data=cp.execFileSync('curl',['-fsS',`http://127.0.0.1:3773${asset}`]);
  if(!data.length || data.subarray(0,100).toString().toLowerCase().includes('<!doctype html>'))throw Error('Invalid UI asset');
  console.log('UI asset served:',asset,data.length,'bytes');
}
JS
    ;;
esac
CHECKS
