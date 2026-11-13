param([Parameter(Mandatory=$true)][ValidateSet("unpack","start","render","refresh")][string]$Step)
switch ($Step) {
'unpack' {
$ErrorActionPreference = 'Stop'
Write-Host "Windows version $([Environment]::OSVersion.Version); Windows PowerShell $($PSVersionTable.PSVersion)"
Write-Host "Runner system Node: $(node --version)"
$dest = Join-Path $env:RUNNER_TEMP '训练营 空格 & 月'
$zip = Join-Path $env:RUNNER_TEMP 'student-public.zip'
Invoke-WebRequest -UseBasicParsing 'https://github.com/hanyyyou/eggmoon-workbench/releases/download/v2026.11.13.1/story-camp-workbench.zip' -OutFile $zip
$pkgHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
Write-Host "SHA256 $pkgHash"
if ($pkgHash -ne '2adc28d649788d9ce5d3e2bc51ccbf9d8568c12eb46f11080a48f7dc117d953a') { throw 'Unexpected release asset' }
Expand-Archive -LiteralPath $zip -DestinationPath $dest
$app = Join-Path $dest 'story-camp'
$skill = Join-Path $app '.codebuddy\skills\camp-story-news\SKILL.md'
if (!(Test-Path -LiteralPath $skill) -or !(Test-Path -LiteralPath (Join-Path $app 'open.cmd'))) { throw 'The extracted package is incomplete.' }

$workBuddyHome = Join-Path $env:USERPROFILE '.workbuddy'
$versions = Join-Path $workBuddyHome 'binaries\node\versions'
$private = Join-Path $versions 'current'
[void](New-Item -ItemType Directory -Path $private -Force)
$installer = Join-Path $env:RUNNER_TEMP 'workbuddy-official.exe'
$official = 'https://download.codebuddy.cn/workbuddy/saas/win32-x64-user/WorkBuddy-win32-x64-user-5.9.3.42398134-d4692421.exe'
curl.exe -fsSL --max-time 180 --retry 1 $official -o $installer
if ($LASTEXITCODE -ne 0) { throw 'The official WorkBuddy installer could not be downloaded.' }
$verifiedHash = (Get-FileHash -LiteralPath $installer -Algorithm SHA256).Hash
if ($verifiedHash -ne 'b5edb52bd6c5b6c7296cf2fff697b019c86d11992a8a814c3010d611896852f9') { throw "WorkBuddy publisher digest mismatch: $verifiedHash" }
$archive = Join-Path $env:RUNNER_TEMP 'official-wb.7z'
python -c "from pathlib import Path;import sys;Path(sys.argv[2]).write_bytes(Path(sys.argv[1]).read_bytes()[276333:276333+449257893])" $installer $archive
if ($LASTEXITCODE -ne 0) { throw 'Failed to read the vendor archive' }
$archiveDir = Join-Path $env:RUNNER_TEMP 'vendor-files'
& 7z x $archive 'resources/vendor/node.zip' "-o$archiveDir" -y
if ($LASTEXITCODE -ne 0) { throw 'WorkBuddy Node archive extraction failed.' }
Expand-Archive -LiteralPath (Join-Path $archiveDir 'resources\vendor\node.zip') -DestinationPath $private
$node = Get-ChildItem $private -Recurse -Filter 'node.exe' | Select-Object -First 1
if (!$node) { throw 'The actual WorkBuddy Node executable was not found.' }
if ($node.Directory.FullName -ne $private) { Copy-Item -LiteralPath $node.FullName -Destination (Join-Path $private 'node.exe') }
Write-Host "Official WorkBuddy Windows runtime: $(& (Join-Path $private 'node.exe') --version)"

$data = Join-Path $env:RUNNER_TEMP '测试学员 数据'
"CAMP_PACKAGE=$app" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
"EGGMOON_WORKBENCH_HOME=$data" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
}
'start' {
$ErrorActionPreference = 'Stop'
$env:EGGMOON_WORKBENCH_OFFLINE = '1'
Set-Location -LiteralPath $env:CAMP_PACKAGE
& .\open.cmd start-service
if ($LASTEXITCODE -ne 0) { throw "open.cmd start exit $LASTEXITCODE" }
& .\open.cmd status
if ($LASTEXITCODE -ne 0) { throw 'open.cmd status failed' }
$base = 'http://127.0.0.1:18377'
$health = Invoke-RestMethod "$base/api/health"
if (!$health.ok -or $health.app -ne 'eggmoon-training-workbench') { throw 'Unexpected health response' }
$service = Get-NetTCPConnection -LocalPort 18377 -State Listen
$process = Get-Process -Id $service.OwningProcess
Write-Host "Serving with: $($process.Path)"
if ($process.Path -notlike '*\.workbuddy\binaries\node\versions\*') { throw 'The expected WorkBuddy runtime was not selected.' }
foreach ($platform in @('fanqie-long','faloo','royalroad')) {
  $board = Invoke-RestMethod "$base/api/camp/rankings?platform=$platform"
  if ($board.status -ne 'ready' -or !$board.items.Count -or !$board.items[0].title) { throw "$platform has no usable titles" }
  Write-Host "$platform $($board.items.Count) titles"
}
$news = Invoke-RestMethod "$base/api/camp/social-news"
if (!$news.items.Count -or $news.items[0].url -notmatch '^https://') { throw 'No readable seed news' }
Write-Host "News items $($news.items.Count)"
$html = Invoke-WebRequest -UseBasicParsing "$base/workspace?platform=faloo"
if ($html.StatusCode -ne 200 -or $html.Content -notmatch 'script') { throw 'Workspace HTML not available' }
}
'render' {
$ErrorActionPreference = 'Stop'
$base = 'http://127.0.0.1:18377'
$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (!(Test-Path -LiteralPath $edge)) { throw 'Edge is missing' }
$ud = Join-Path $env:RUNNER_TEMP 'camp-edge'
$ErrorActionPreference = 'Continue'
$page = (& $edge '--headless' '--disable-gpu' '--no-sandbox' '--no-first-run' "--user-data-dir=$ud" '--virtual-time-budget=10000' '--dump-dom' "$base/workspace?platform=faloo" 2>$null | Out-String)
$rows = [regex]::Matches($page, 'class="camp-book(?: |")').Count
if (!$rows) { throw 'No visible book rows found in Edge DOM' }
$newsPage = (& $edge '--headless' '--disable-gpu' '--no-sandbox' '--no-first-run' "--user-data-dir=$ud" '--virtual-time-budget=10000' '--dump-dom' "$base/workspace?view=social-news" 2>$null | Out-String)
$articles = [regex]::Matches($newsPage, 'class="camp-news-open"').Count
if (!$articles) { throw 'No articles rendered in Edge DOM' }
Write-Host "Edge rendered $rows books and $articles original reports"
}
'refresh' {
$ErrorActionPreference = 'Stop'
Set-Location -LiteralPath $env:CAMP_PACKAGE
& .\open.cmd stop
if ($LASTEXITCODE -ne 0) { throw "open.cmd stop exit $LASTEXITCODE" }
$env:EGGMOON_WORKBENCH_OFFLINE = '1'
$service = Start-Process -FilePath $env:ComSpec -ArgumentList '/d /c open.cmd serve' -WorkingDirectory $env:CAMP_PACKAGE -PassThru
try {
  $ready = $false
  foreach ($try in 1..30) {
    try { $health = Invoke-RestMethod 'http://127.0.0.1:18377/api/health'; if ($health.ok) { $ready = $true; break } } catch { Start-Sleep -Milliseconds 300 }
  }
  if (!$ready -or $service.HasExited) { throw 'Foreground managed serve failed' }
  & .\open.cmd stop
  if ($LASTEXITCODE -ne 0 -or !$service.WaitForExit(15000)) { throw 'Foreground service did not exit cleanly on stop' }
  Write-Host 'Foreground service started, answered and exited cleanly'
} finally { if (!$service.HasExited) { $service.Kill() } }
Remove-Item Env:EGGMOON_WORKBENCH_OFFLINE
$toolDir = Join-Path $env:RUNNER_TEMP 'camp-browser-qa'
[void](New-Item -ItemType Directory -Force -Path $toolDir)
& npm.cmd install --prefix $toolDir --ignore-scripts --no-audit --no-fund playwright-core@1.61.1
if ($LASTEXITCODE -ne 0) { throw 'Unable to install browser test driver.' }
$env:NODE_PATH = Join-Path $toolDir 'node_modules'
$probe = Join-Path $toolDir 'browser.cjs'
$js = @'
const {chromium} = require('playwright-core');
const crypto = require('node:crypto');
const fs = require('node:fs/promises');
const assert = require('node:assert/strict');

(async () => {
  const browser = await chromium.launch({channel:'msedge',headless:true});
  const page = await browser.newPage({acceptDownloads:true});
  let full = false;
  try {
    for (const platform of ['ciweimao','faloo']) {
      await page.goto('http://127.0.0.1:18377/workspace?platform='+platform, {waitUntil:'domcontentloaded'});
      const select = page.locator('button.camp-book-title').first();
      await select.click({timeout:30_000});
      const action = page.getByRole('button',{name:'下载前10章', exact:true});
      await action.waitFor({state:'visible'});
      const response = page.waitForResponse(res => res.url().includes('/api/camp/book-chapters?') && res.request().method()==='POST',{timeout:190_000});
      let got;
      const onDownload = download => {got=download};
      page.once('download', onDownload);
      await action.click();
      const res=await response;
      const body=await res.json();
      const chapters=Array.isArray(body.chapters)?body.chapters:[];
      if(!chapters.length) {
        page.removeListener('download',onDownload);
        console.log(JSON.stringify({platform,status:res.status(),chapters:0,sourceStatus:(body.message||body.error||'').slice(0,180)}));
        continue;
      }
      assert.ok(chapters.length<=10);
      assert.ok(chapters.every(c=>c.text?.trim() && c.title?.trim() && c.url?.startsWith('http')));
      await page.waitForFunction(()=>document.querySelector('.camp-chapter-export [role="status"]')?.textContent?.includes('TXT'),null,{timeout:12000});
      if (!got) got=await page.waitForEvent('download',{timeout:10000});
      assert.ok(got.suggestedFilename().endsWith('前'+chapters.length+'章.txt'));
      const raw=await fs.readFile(await got.path());
      const value=raw.toString('utf8').replace(/\r\n/g,'\n');
      for (const ch of chapters) {
        assert.ok(value.includes(ch.url) && value.includes(ch.text.trim().replace(/\r\n?/g,'\n')));
      }
      console.log(JSON.stringify({platform,status:res.status(),chapters:chapters.length,byteLength:raw.length,sha256:crypto.createHash('sha256').update(raw).digest('hex')}));
      await got.delete();
      if(chapters.length===10) {full=true;break;}
    }
    if(!full) throw Error('Neither tested platform supplied all ten public chapters from this Windows runner.');
  } finally {await browser.close();}
})().catch(err=>{console.error(err.message);process.exitCode=1;});


'@
Set-Content -LiteralPath $probe -Value $js -Encoding UTF8
& .\open.cmd start-service
if ($LASTEXITCODE -ne 0) { throw 'Failed to start online service.' }
try {
  & node $probe
  if ($LASTEXITCODE -ne 0) { throw 'Real chapter download in Edge did not pass.' }
} finally {
  & .\open.cmd stop
}
exit 0
}
}
