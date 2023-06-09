[cmdletbinding()]
param (
 [Parameter(Mandatory = $True)]
 [Alias('DCs')]
 [string[]]$DomainControllers,
 [Parameter(Mandatory = $True)]
 [System.Management.Automation.PSCredential]$ADCredential,
 [Parameter(Mandatory = $True)]
 [string]$SearchBase,
 [Parameter(Mandatory = $True)]
 [string]$TargetGroup,
 [Parameter(Mandatory = $True)]
 [string[]]$ExcludeGroups,
 [int]$MonthsSinceLastLogon,
 [Alias('wi')]
 [SWITCH]$WhatIf
)

function Clear-Group ($group) {
 begin {
  $groupSams = (Get-ADGroupMember -Identity $group).SamAccountName
  $msg = $MyInvocation.MyCommand.Name, $group, $groupSams.count
  Write-Host ('{0},{1},{2}' -f $msg) -Fore Green
 }
 process {
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $group)
  Remove-ADGroupMember $group $GroupSams -Confirm:$false -WhatIf:$WhatIf
 }
}

function Get-CurrentADStaffObjs ($cutoffMonths) {
 begin {
  $cutOffdate = (Get-Date).AddMonths(-$cutoffMonths)
  $aDParams = @{
   Filter     = {
    ( mail -like "*@*" ) -and
    ( employeeID -like "*" ) -and
    ( enabled -eq $True )
   }
   Properties = 'employeeId', 'lastLogonDate', 'Description', 'AccountExpirationDate'
   Searchbase = $SearchBase
  }
 }
 process {
  # Paid staff members emplid are generated by Escape and are currently in the 4-6 digit range.
  # The regex "^\d{4,6}$" accounts for this limit.
  $currentStaff = Get-Aduser @aDParams | Where-Object {
  (($_.employeeId -match "^\d{4,6}$") -and ($_.lastLogonDate -gt $cutOffdate)) -or
  ($_.Description -like "*Board*Member*")
  }
  $msg = $MyInvocation.MyCommand.Name, $currentStaff.count
  Write-Host ('{0},Count: {1}' -f $msg) -Fore Green
  $currentStaff
 }
}

function Get-ExcludedSams {
 begin {
 }
 process {
  $sams = (Get-ADGroupMember -Identity $_).SamAccountName
  Write-Host ('{0},[{1}],count: {2}' -f $MyInvocation.MyCommand.Name, $_, $sams.count)
  $sams
 }
}

function Select-ValidSams ($excludedSams) {
 process {
  if ($excludedSams -contains $_.SamAccountName) { return }
  $_.SamAccountName
 }
}

function Update-GroupMembers ($group, $validSams) {
 process {
  $addMembers = @{
   Identity = $group
   Members  = $validSams
   Confirm  = $false
   WhatIf   = $WhatIf
  }
  Write-Host ('{0},{1}' -f $MyInvocation.MyCommand.Name, $group)
  Add-ADGroupMember @addMembers
 }
}

# ========================== Main ===========================
# Imported Functions
. .\lib\Clear-SessionData.ps1
. .\lib\New-ADSession.ps1
. .\lib\Select-DomainController.ps1
. .\lib\Show-TestRun.ps1

Show-TestRun
Clear-SessionData

$dc = Select-DomainController $DomainControllers
$adCmdLets = 'Get-ADUser', 'Get-ADGroup', 'Get-ADGroupMember', 'Add-ADGroupMember', 'Remove-ADGroupMember'
New-ADSession -dc $dc -cmdlets $adCmdLets -cred $ADCredential

$excludedSams = $ExcludeGroups | Get-ExcludedSams
$currentADStaff = Get-CurrentADStaffObjs $MonthsSinceLastLogon

$validSams = $currentADStaff | Select-ValidSams $excludedSams
Write-Host ('{0},Valid Sams Count: {1}' -f $MyInvocation.MyCommand.Name, $validSams.count)

Clear-Group $TargetGroup
Update-GroupMembers $TargetGroup $validSams

Clear-SessionData
Show-TestRun