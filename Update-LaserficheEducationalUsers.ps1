[cmdletbinding()]
param (
 [Parameter(Mandatory = $True)][PSCredential]$ADCredential,
 [Parameter(Mandatory = $True)][string]$SearchBase,
 [Parameter(Mandatory = $True)][string]$TargetGroup,
 [Parameter(Mandatory = $True)][string[]]$ExcludeGroups,
 [Parameter(Mandatory = $True)][string[]]$ExcludeDescriptions,
 [int]$MonthsSinceLastLogon,
 [Alias('wi')][SWITCH]$WhatIf
)

function Clear-Group ($group, [pscredential]$cred) {
 begin {
  $groupSams = (Get-ADGroupMember -Identity $group -Credential $cred).SamAccountName
 }
 process {
  $params = @{
   Identity   = $group
   Members    = $groupSams
   Confirm    = $false
   Credential = $cred
   WhatIf     = $WhatIf
  }
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $group) -F Magenta
  Remove-ADGroupMember @params
 }
}

function Get-CurrentADStaffObjs ($months, $ou, [pscredential]$cred) {
 $cutOffDate = (Get-Date).AddMonths(-$months)
 $filter = "
   (mail -like '*@*') -and (employeeID -like '*') -and (enabled -eq 'True') -and
   (LastLogonDate -ge `$cutOffDate) -and -not(EmployeeType -eq 'student')
  "
 $params = @{
  Filter     = $filter
  Properties = 'EmployeeId', 'lastLogonDate', 'Description', 'AccountExpirationDate'
  SearchBase = $ou
  Credential = $cred
 }

 $result = Get-ADUser @params
 $msg = $MyInvocation.MyCommand.Name, @($result).count
 Write-Host ('{0},Count: {1}' -f $msg) -Fore Green
 $result
}

function Get-ExcludedSams ( [pscredential]$cred) {
 process {
  $sams = (Get-ADGroupMember -Identity $_ -Credential $cred).SamAccountName
  Write-Host ('{0},[{1}],count: {2}' -f $MyInvocation.MyCommand.Name, $_, $sams.count) -F Green
  $sams
 }
}

function Skip-Excluded ($samids) {
 process {
  $_ | Where-Object { $samids -notcontains $_.SamAccountName }
 }
}

function Show-Object {
 process {
  Write-Verbose ( '{0},{1},{2}' -f $MyInvocation.MyCommand.Name, $_.SamAccountName, $_.Description | Out-String)
  $_
 }
}

function Skip-Descriptions ($descriptions) {
 begin {
  $escapedItems = $descriptions | ForEach-Object { [regex]::Escape($_) }
  $pattern = $escapedItems -join '|'
 }
 process {
  if (($_.Description -match $pattern)) {
   Write-Verbose ('{0},{1},{2},{3}' -f $MyInvocation.MyCommand.Name, $_.SamAccountName, $_.Description, $pattern)
   return
  }
  $_
 }
}

function Update-GroupMembers ($group, $validSams, [pscredential]$cred) {
 process {
  $addMembers = @{
   Identity   = $group
   Members    = $validSams
   Confirm    = $false
   Credential = $cred
   WhatIf     = $WhatIf
  }
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $group)
  Add-ADGroupMember @addMembers
  $result = Get-ADGroupMember -Identity $group -Credential $cred
  Write-Host ('{0},[{1}],count: {2}' -f $MyInvocation.MyCommand.Name, $group, @($result).count) -Fore Green
 }
}

# ============================================================================================
Import-Module -Name CommonScriptFunctions
$adCmdLets = 'Get-ADUser', 'Get-ADGroup', 'Get-ADGroupMember', 'Add-ADGroupMember', 'Remove-ADGroupMember'
Import-Module -Name ActiveDirectory -Cmdlet $adCmdLets -WarningAction SilentlyContinue -ErrorAction Stop

if ($WhatIf) { Show-TestRun }
Show-BlockInfo main

$excludedSams = $ExcludeGroups | Get-ExcludedSams -cred $ADCredential
$currentADStaff = Get-CurrentADStaffObjs -months $MonthsSinceLastLogon -ou $SearchBase -cred $ADCredential

$validSams = $currentADStaff |
 Skip-Excluded $excludedSams |
  Skip-Descriptions $ExcludeDescriptions |
   Show-Object
Write-Host ('{0},Valid Sams Count: {1}' -f $MyInvocation.MyCommand.Name, @($validSams).count) -Fore Green

Clear-Group -group $TargetGroup -cred $ADCredential
Update-GroupMembers -group $TargetGroup -validSams $validSams -cred $ADCredential

Show-BlockInfo End
if ($WhatIf) { Show-TestRun }