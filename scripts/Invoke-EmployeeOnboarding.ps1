<#
.SYNOPSIS
Validates synthetic employee intake and writes a simulated provisioning plan.
.DESCRIPTION
Uses local access rules to produce CSV, JSON, and HTML reports. No accounts are
created and no external services are contacted. Reports replace the previous run.
Requires Windows PowerShell 5.1 or later with its normal FullLanguage mode.
Exit codes: 0 = all ready, 2 = completed with exceptions, 1 = batch failure.
.PARAMETER CsvPath
Required path to a UTF-8 CSV. Relative paths use the caller's working directory.
.EXAMPLE
.\scripts\Invoke-EmployeeOnboarding.ps1 -CsvPath .\data\new_hires.csv
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$CsvPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$requiredFields = @('EmployeeID', 'FirstName', 'LastName', 'Department',
    'JobTitle', 'Manager', 'StartDate', 'Email', 'EmploymentType', 'Location')

function Assert-StringArray {
    param($Value, [string]$Name, [switch]$Unique)
    if ($Value -isnot [array] -or $Value.Count -eq 0) {
        throw "$Name must be a nonempty array."
    }
    $seen = @{}
    foreach ($item in $Value) {
        if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace($item)) {
            throw "$Name must contain nonblank strings."
        }
        if ($Unique -and $seen.ContainsKey($item)) { throw "$Name contains duplicate values." }
        $seen[$item] = $true
    }
}

function Assert-UniqueJsonKeys {
    param([string]$Json)
    # ConvertFrom-Json can hide duplicate keys, so check the original JSON too.
    $tokens = [regex]::Matches($Json, '"(?:\\.|[^"\\])*"|[{}\[\]:]')
    $scopes = New-Object System.Collections.Stack
    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = $tokens[$i].Value
        if ($token -eq '{' -or $token -eq '[') { $scopes.Push(@{}); continue }
        if ($token -eq '}' -or $token -eq ']') { $null = $scopes.Pop(); continue }
        if ($token.StartsWith('"') -and $i + 1 -lt $tokens.Count -and $tokens[$i + 1].Value -eq ':') {
            $key = (ConvertFrom-Json -InputObject ('{"Value":' + $token + '}')).Value
            $keys = $scopes.Peek()
            if ($keys.ContainsKey($key)) { throw "Duplicate configuration key: $key" }
            $keys[$key] = $true
        }
    }
}

function Read-AccessRules {
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    $json = $encoding.GetString($bytes).TrimStart([char]0xFEFF)
    $rules = ConvertFrom-Json -InputObject $json
    Assert-UniqueJsonKeys -Json $json
    if ($rules -isnot [pscustomobject]) { throw 'Configuration must be a JSON object.' }
    if (($rules.SchemaVersion -isnot [int] -and $rules.SchemaVersion -isnot [long]) -or $rules.SchemaVersion -ne 1) {
        throw 'SchemaVersion must be 1.'
    }
    if ($rules.RuleSetVersion -isnot [string] -or [string]::IsNullOrWhiteSpace($rules.RuleSetVersion)) {
        throw 'RuleSetVersion must be a nonempty string.'
    }
    Assert-StringArray $rules.AllowedDepartments 'AllowedDepartments' -Unique
    Assert-StringArray $rules.AllowedEmploymentTypes 'AllowedEmploymentTypes' -Unique
    Assert-StringArray $rules.BaseGroups 'BaseGroups' -Unique
    if ($rules.DepartmentRules -isnot [pscustomobject]) { throw 'DepartmentRules must be an object.' }
    foreach ($property in $rules.DepartmentRules.PSObject.Properties) {
        if ($rules.AllowedDepartments -notcontains $property.Name) {
            throw "Unknown department rule: $($property.Name)"
        }
        Assert-StringArray $property.Value "DepartmentRules.$($property.Name)"
    }
    if ($rules.JobTitleRules -isnot [array]) { throw 'JobTitleRules must be an array.' }
    $pairs = @{}
    foreach ($rule in $rules.JobTitleRules) {
        if ($rule -isnot [pscustomobject] -or $rule.Department -isnot [string] -or
            $rules.AllowedDepartments -notcontains $rule.Department -or
            $rule.JobTitle -isnot [string] -or [string]::IsNullOrWhiteSpace($rule.JobTitle)) {
            throw 'Each job-title rule needs an allowed Department and a nonblank JobTitle.'
        }
        if (-not $pairs.ContainsKey($rule.Department)) { $pairs[$rule.Department] = @{} }
        if ($pairs[$rule.Department].ContainsKey($rule.JobTitle)) { throw 'Duplicate department/title rule.' }
        $pairs[$rule.Department][$rule.JobTitle] = $true
        Assert-StringArray $rule.Groups 'JobTitleRules.Groups'
    }
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    [pscustomobject]@{ Rules = $rules; Hash = $hash }
}

function Read-CsvRows {
    param([string]$Text)
    # Keep blank records and quoted fields, including commas and embedded newlines.
    $fields = New-Object 'System.Collections.Generic.List[string]'
    $value = New-Object System.Text.StringBuilder
    $state = 'Start'
    $recordStarted = $false
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $character = $Text[$i]
        $recordStarted = $true
        if ($state -eq 'Quoted') {
            if ($character -eq '"') {
                if ($i + 1 -lt $Text.Length -and $Text[$i + 1] -eq '"') {
                    $null = $value.Append('"'); $i++
                } else { $state = 'Closed' }
            } else { $null = $value.Append($character) }
            continue
        }
        if ($character -eq ',' -or $character -eq "`r" -or $character -eq "`n") {
            $fields.Add($value.ToString())
            $null = $value.Clear()
            $state = 'Start'
            if ($character -ne ',') {
                [pscustomobject]@{ Fields = $fields.ToArray() }
                $fields.Clear()
                $recordStarted = $false
                if ($character -eq "`r" -and $i + 1 -lt $Text.Length -and $Text[$i + 1] -eq "`n") { $i++ }
            }
            continue
        }
        if ($state -eq 'Closed') { throw 'Malformed CSV: unexpected text after a closing quote.' }
        if ($character -eq '"') {
            if ($state -ne 'Start') { throw 'Malformed CSV: quote inside an unquoted field.' }
            $state = 'Quoted'
        } else {
            $null = $value.Append($character)
            $state = 'Unquoted'
        }
    }
    if ($state -eq 'Quoted') { throw 'Malformed CSV: unclosed quoted field.' }
    if ($recordStarted) {
        $fields.Add($value.ToString())
        [pscustomobject]@{ Fields = $fields.ToArray() }
    }
}

function Read-OnboardingCsv {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw 'CSV file does not exist.' }
    $fullPath = (Resolve-Path -LiteralPath $Path).ProviderPath
    $encoding = New-Object System.Text.UTF8Encoding($false, $true)
    $text = $encoding.GetString([System.IO.File]::ReadAllBytes($fullPath)).TrimStart([char]0xFEFF)
    $rows = @(Read-CsvRows -Text $text)
    if ($rows.Count -eq 0) { throw 'CSV has no header or employee records.' }
    $headers = $rows[0].Fields
    $seen = @{}
    foreach ($header in $headers) {
        if ([string]::IsNullOrWhiteSpace($header)) { throw 'CSV contains a blank header.' }
        if ($seen.ContainsKey($header)) { throw "Duplicate CSV header: $header" }
        $seen[$header] = $true
    }
    foreach ($field in $requiredFields) {
        if ($headers -cnotcontains $field) { throw "Missing required CSV header: $field" }
    }
    if ($rows.Count -eq 1) { throw 'CSV contains no employee records.' }
    for ($index = 1; $index -lt $rows.Count; $index++) {
        $values = $rows[$index].Fields
        # A physically blank record also represents an employee with missing fields.
        $blank = $values.Count -eq 1 -and [string]::IsNullOrWhiteSpace($values[0])
        if (-not $blank -and $values.Count -ne $headers.Count) {
            throw "Malformed CSV: field count mismatch at SourceRow $index."
        }
        $record = [ordered]@{ SourceRow = $index }
        for ($column = 0; $column -lt $headers.Count; $column++) {
            if ($requiredFields -ccontains $headers[$column]) {
                $record[$headers[$column]] = if ($blank) { '' } else { $values[$column].Trim() }
            }
        }
        [pscustomobject]$record
    }
}

function Get-DuplicateValues {
    param([object[]]$Records, [string]$Field)
    # Count the whole feed, including invalid records; neither duplicate is a winner.
    $counts = @{}
    foreach ($record in $Records) {
        $value = $record.$Field
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            if (-not $counts.ContainsKey($value)) { $counts[$value] = 0 }
            $counts[$value]++
        }
    }
    $duplicates = @{}
    foreach ($key in $counts.Keys) { if ($counts[$key] -gt 1) { $duplicates[$key] = $true } }
    return $duplicates
}

function Test-EmployeeRecord {
    param($Record, $Rules, [hashtable]$DuplicateIds, [hashtable]$DuplicateEmails)
    foreach ($field in $requiredFields) {
        if ([string]::IsNullOrWhiteSpace($Record.$field)) { "Missing required field: $field" }
    }
    if ($Record.Department) {
        $departmentMatch = @($Rules.AllowedDepartments | Where-Object { $_ -eq $Record.Department })
        if ($departmentMatch.Count -eq 0) { "Unknown department: $($Record.Department)" }
        else { $Record.Department = $departmentMatch[0] }
    }
    if ($Record.EmploymentType) {
        $employmentTypeMatch = @($Rules.AllowedEmploymentTypes | Where-Object { $_ -eq $Record.EmploymentType })
        if ($employmentTypeMatch.Count -eq 0) { "Unsupported employment type: $($Record.EmploymentType)" }
        else { $Record.EmploymentType = $employmentTypeMatch[0] }
    }
    if ($Record.Email -and $Record.Email -notmatch '^[^\s@]+@[^\s@]+\.[^\s@]+$') { 'Invalid email address' }
    $date = [datetime]::MinValue
    if ($Record.StartDate -and -not [datetime]::TryParseExact($Record.StartDate, 'yyyy-MM-dd',
        [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$date)) {
        'Invalid start date'
    }
    if ($Record.EmployeeID -and $DuplicateIds.ContainsKey($Record.EmployeeID)) { 'Duplicate EmployeeID' }
    if ($Record.Email -and $DuplicateEmails.ContainsKey($Record.Email)) { 'Duplicate email address' }
}

function Get-AccessAssignment {
    param($Record, $Rules)
    $departmentRule = $Rules.DepartmentRules.PSObject.Properties[$Record.Department]
    if ($null -eq $departmentRule) {
        return [pscustomobject]@{ Reason = "Missing access rule for department: $($Record.Department)"; Groups = @(); AppliedRules = @() }
    }
    $appliedRules = @(
        [pscustomobject]@{ RuleType = 'Base'; RuleKey = 'BaseGroups'; Groups = @($Rules.BaseGroups) }
        [pscustomobject]@{ RuleType = 'Department'; RuleKey = $Record.Department; Groups = @($departmentRule.Value) }
    )
    foreach ($rule in $Rules.JobTitleRules) {
        if ($rule.Department -eq $Record.Department -and $rule.JobTitle -eq $Record.JobTitle) {
            $appliedRules += [pscustomobject]@{ RuleType = 'JobTitle'; RuleKey = "$($Record.Department)/$($rule.JobTitle)"; Groups = @($rule.Groups) }
        }
    }
    $seen = @{}
    $groups = @(foreach ($rule in $appliedRules) {
        foreach ($group in $rule.Groups) {
            if (-not $seen.ContainsKey($group)) { $group; $seen[$group] = $true }
        }
    })
    [pscustomobject]@{ Reason = ''; Groups = $groups; AppliedRules = $appliedRules }
}

function New-ProcessingResult {
    param($Record, [string[]]$Reasons, [object[]]$Groups, [object[]]$AppliedRules,
        [string]$RunId, $Configuration)
    $status = 'Ready for Provisioning'
    if ($Reasons.Count -gt 0) { $status = 'Exception'; $Groups = @(); $AppliedRules = @() }
    [pscustomobject][ordered]@{
        RunId = $RunId
        Timestamp = [datetime]::UtcNow.ToString('o')
        SourceRow = $Record.SourceRow
        EmployeeID = $Record.EmployeeID
        EmployeeName = (@($Record.FirstName, $Record.LastName | Where-Object { $_ }) -join ' ')
        Email = $Record.Email
        Department = $Record.Department
        JobTitle = $Record.JobTitle
        Status = $status
        AssignedGroups = @($Groups)
        ExceptionReason = $Reasons -join '; '
        AppliedRules = @($AppliedRules)
        RuleSetVersion = $Configuration.Rules.RuleSetVersion
        ConfigSha256 = $Configuration.Hash
    }
}

function ConvertTo-SafeCsvCell {
    param([string]$Value)
    if ($Value -match '^[=+\-@]') { return "'$Value" }
    return $Value
}

function ConvertTo-HtmlText {
    param($Value)
    [System.Net.WebUtility]::HtmlEncode([string]$Value)
}

function Write-OnboardingReports {
    param([object[]]$Results, [string]$OutputPath, [string]$RunId, [string]$RunTime)
    $null = New-Item -ItemType Directory -Path $OutputPath -Force
    $names = @('ProvisioningPlan.csv', 'AuditLog.json', 'OnboardingSummary.html')
    $temporary = @($names | ForEach-Object { Join-Path $OutputPath ('.' + $RunId + '.' + $_ + '.tmp') })
    try {
        $csvRows = foreach ($result in $Results) {
            $row = [ordered]@{
                SourceRow = $result.SourceRow; EmployeeID = $result.EmployeeID
                EmployeeName = $result.EmployeeName; Email = $result.Email
                Department = $result.Department; JobTitle = $result.JobTitle
                AssignedGroups = $result.AssignedGroups -join ';'; Status = $result.Status
                ExceptionReason = $result.ExceptionReason; ProcessedAt = $result.Timestamp
            }
            foreach ($key in @($row.Keys)) { $row[$key] = ConvertTo-SafeCsvCell ([string]$row[$key]) }
            [pscustomobject]$row
        }
        $csvRows | Export-Csv -LiteralPath $temporary[0] -NoTypeInformation -Encoding UTF8
        ConvertTo-Json -InputObject @($Results) -Depth 8 | Set-Content -LiteralPath $temporary[1] -Encoding UTF8
        $exceptions = @($Results | Where-Object { $_.Status -eq 'Exception' }).Count
        $ready = $Results.Count - $exceptions
        $rate = (100.0 * $exceptions / $Results.Count).ToString('F1', [cultureinfo]::InvariantCulture)
        $table = foreach ($result in $Results) {
            $details = if ($result.Status -eq 'Exception') { $result.ExceptionReason } else { $result.AssignedGroups -join '; ' }
            $cells = @($result.SourceRow, $result.EmployeeName, $result.Department, $result.JobTitle, $result.Status, $details)
            $class = if ($result.Status -eq 'Exception') { 'exception' } else { 'ready' }
            '<tr class="' + $class + '">' + (($cells | ForEach-Object { '<td>' + (ConvertTo-HtmlText $_) + '</td>' }) -join '') + '</tr>'
        }
        $html = @"
<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Employee Onboarding Summary</title>
<style>
body{font-family:Segoe UI,Arial,sans-serif;margin:2rem;color:#243247;background:#f5f7fa}
h1{margin-bottom:.5rem} .meta{overflow-wrap:anywhere} .totals{padding:1rem;background:#fff;border-left:4px solid #356493;line-height:1.8}
.table-wrap{overflow-x:auto} table{border-collapse:collapse;width:100%;background:#fff;margin-top:1.5rem}
th,td{text-align:left;padding:.7rem;border:1px solid #d5dce5;vertical-align:top;overflow-wrap:anywhere}
th{background:#243247;color:#fff} .exception{background:#fff3e5} td:nth-child(5){min-width:9rem}
caption{text-align:left;font-weight:600;padding:.5rem 0} footer{margin-top:1rem}
</style></head><body>
<h1>Employee Onboarding Summary</h1><p>Simulated provisioning plan. No accounts or access changes were made.</p>
<p class="meta">Run ID: $(ConvertTo-HtmlText $RunId)<br>UTC time: $(ConvertTo-HtmlText $RunTime)</p>
<div class="totals">Records Processed: $(ConvertTo-HtmlText $Results.Count)<br>Ready for Provisioning: $(ConvertTo-HtmlText $ready)<br>Exceptions: $(ConvertTo-HtmlText $exceptions)<br>Exception Rate: $(ConvertTo-HtmlText $rate)%</div>
<div class="table-wrap"><table><caption>Employee results in source order</caption><thead><tr><th scope="col">Source Row</th><th scope="col">Employee</th><th scope="col">Department</th><th scope="col">Job Title</th><th scope="col">Status</th><th scope="col">Details</th></tr></thead>
<tbody>$($table -join "`n")</tbody></table></div><footer>Exceptions have no assigned access. Reports are replaced on each completed run.</footer>
</body></html>
"@
        Set-Content -LiteralPath $temporary[2] -Value $html -Encoding UTF8
        # Serialize all three before replacing any prior reports. Replacement is
        # per file; a filesystem failure can still leave a partially replaced set.
        for ($i = 0; $i -lt $names.Count; $i++) {
            $destination = Join-Path $OutputPath $names[$i]
            if (Test-Path -LiteralPath $destination -PathType Container) {
                throw "Report destination is a directory: $($names[$i])"
            }
            Move-Item -LiteralPath $temporary[$i] -Destination $destination -Force
        }
    }
    finally {
        foreach ($path in $temporary) {
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
        }
    }
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$outputPath = Join-Path $repositoryRoot 'output'
$runId = [guid]::NewGuid().ToString()
$runTime = [datetime]::UtcNow.ToString('o')
try {
    if ([string]::IsNullOrWhiteSpace($CsvPath)) { throw 'CsvPath must not be blank.' }
    $configuration = Read-AccessRules (Join-Path $repositoryRoot 'config/access_rules.json')
    $records = @(Read-OnboardingCsv -Path $CsvPath)
    $duplicateIds = Get-DuplicateValues $records 'EmployeeID'
    $duplicateEmails = Get-DuplicateValues $records 'Email'
}
catch {
    Write-Host "Batch input/configuration error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Existing reports were not changed.'
    exit 1
}

Write-Host "Employee onboarding simulation | Run $runId"
$results = @(foreach ($record in $records) {
    $reasons = @(); $groups = @(); $appliedRules = @()
    try {
        $reasons = @(Test-EmployeeRecord $record $configuration.Rules $duplicateIds $duplicateEmails)
        if ($reasons.Count -eq 0) {
            $assignment = Get-AccessAssignment $record $configuration.Rules
            if ($assignment.Reason) { $reasons = @($assignment.Reason) }
            else { $groups = @($assignment.Groups); $appliedRules = @($assignment.AppliedRules) }
        }
        $result = New-ProcessingResult $record $reasons $groups $appliedRules $runId $configuration
    }
    catch {
        $result = New-ProcessingResult $record @('Processing error') @() @() $runId $configuration
    }
    Write-Host ("[{0:D2}] {1}: {2}{3}" -f $record.SourceRow, $result.EmployeeName, $result.Status,
        $(if ($result.ExceptionReason) { ' - ' + $result.ExceptionReason } else { '' }))
    $result
})

try { Write-OnboardingReports $results $outputPath $runId $runTime }
catch {
    Write-Host "Report output error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host 'Reports may be stale or incomplete. This batch did not complete successfully.'
    exit 1
}
$exceptionCount = @($results | Where-Object { $_.Status -eq 'Exception' }).Count
$exceptionRate = (100.0 * $exceptionCount / $results.Count).ToString('F1', [cultureinfo]::InvariantCulture)
Write-Host "Completed: $($results.Count) processed; $($results.Count - $exceptionCount) Ready for Provisioning; $exceptionCount Exceptions ($exceptionRate%)."
foreach ($name in @('ProvisioningPlan.csv', 'AuditLog.json', 'OnboardingSummary.html')) {
    Write-Host (Join-Path $outputPath $name)
}
if ($exceptionCount -gt 0) { exit 2 }
exit 0
