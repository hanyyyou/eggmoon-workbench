param([Parameter(Mandatory=$true)][ValidateSet("unpack","start","render","refresh")][string]$Step)
switch ($Step) {
'unpack' {
$ErrorActionPreference = 'Stop'
Write-Host "Windows version $([Environment]::OSVersion.Version); Windows PowerShell $($PSVersionTable.PSVersion)"
Write-Host "Runner system Node: $(node --version)"
$dest = Join-Path $env:RUNNER_TEMP '训练营 空格 & 月'
$zip = Join-Path $env:RUNNER_TEMP 'student-public.zip'
Invoke-WebRequest -UseBasicParsing 'https://github.com/hanyyyou/eggmoon-workbench/releases/latest/download/story-camp-workbench.zip' -OutFile $zip
Write-Host "SHA256 $((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash)"
Expand-Archive -LiteralPath $zip -DestinationPath $dest
$app = Join-Path $dest 'story-camp'
$skill = Join-Path $app '.codebuddy\skills\camp-story-news\SKILL.md'
if (!(Test-Path -LiteralPath $skill) -or !(Test-Path -LiteralPath (Join-Path $app 'open.cmd'))) { throw 'The extracted package is incomplete.' }
$data = Join-Path $env:RUNNER_TEMP '测试学员 数据'
"CAMP_PACKAGE=$app" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
"EGGMOON_WORKBENCH_HOME=$data" | Out-File -FilePath $env:GITHUB_ENV -Encoding utf8 -Append
}
'start' {
$ErrorActionPreference = 'Stop'
$env:EGGMOON_WORKBENCH_OFFLINE = '1'
Set-Location -LiteralPath $env:CAMP_PACKAGE
& .\open.cmd start
if ($LASTEXITCODE -ne 0) { throw "open.cmd start exit $LASTEXITCODE" }
& .\open.cmd status
if ($LASTEXITCODE -ne 0) { throw 'open.cmd status failed' }
$base = 'http://127.0.0.1:18377'
$health = Invoke-RestMethod "$base/api/health"
if (!$health.ok -or $health.app -ne 'eggmoon-training-workbench') { throw 'Unexpected health response' }
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
$first = (& .\open.cmd news-refresh | Select-Object -Last 1) | ConvertFrom-Json
$firstExit = $LASTEXITCODE
$second = (& .\open.cmd news-refresh | Select-Object -Last 1) | ConvertFrom-Json
$secondExit = $LASTEXITCODE
Write-Host "First: $($first | ConvertTo-Json -Compress)"
Write-Host "Second: $($second | ConvertTo-Json -Compress)"
if ($first.task -ne 'social-news' -or !$first.checkedAt -or $first.checkedAt -ne $second.checkedAt) { throw 'Daily action did not preserve a single check per calendar day' }
& .\open.cmd status
if ($LASTEXITCODE -eq 0) { throw 'news-refresh unexpectedly started a web server' }
if ($firstExit -ne 0 -or $secondExit -ne 0 -or $second.outcome -ne 'unchanged') { throw "Live sources or update command failed; exits $firstExit / $secondExit" }
exit 0
}
}
