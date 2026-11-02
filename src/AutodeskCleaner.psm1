Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' -File |
    Sort-Object Name | ForEach-Object { . $_.FullName }
Export-ModuleMember -Function '*-Adsk*'
