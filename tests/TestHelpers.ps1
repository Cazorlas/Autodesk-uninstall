function Get-FixtureRows {
    $rows = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'fixtures/arp-host.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    # Windows PowerShell 5.1 emits a JSON array as one pipeline object; enumerate it here.
    $rows
}

function Get-FixturePackage {
    param([string]$Name)
    Get-FixtureRows | Where-Object { $_.DisplayName -eq $Name } | ConvertTo-AdskPackage
}
