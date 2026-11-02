Import-Module Pester -RequiredVersion 3.4.0 -ErrorAction Stop
Invoke-Pester -Path $PSScriptRoot -EnableExit
