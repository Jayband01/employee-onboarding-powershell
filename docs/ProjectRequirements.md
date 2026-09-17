# Input and Report Contract

Exact input, validation, and output rules for the local simulation. See the README for the workflow and run command.

## Assumptions
Target Windows PowerShell 5.1 using built-in commands and .NET types. Full-Time, Part-Time, and Contract employees use the same access policy. Location does not affect access. Manager is required text, not a directory lookup. Dates may be past or future; no current-date cutoff applies. Needs Review is reserved for a future approval workflow and is not emitted in this version.

## Input Data
Use UTF-8 comma-delimited CSV. Required columns, in supplied order:

`EmployeeID, FirstName, LastName, Department, JobTitle, Manager, StartDate, Email, EmploymentType, Location`

Require those exact header names once each; allow extra columns but ignore them. Header order may vary. Reject missing or duplicate headers, malformed CSV structure, unreadable files, and files with no employee records before processing. Do not silently discard parsed blank employee records; required-field checks apply to them. SourceRow is the one-based employee record index, excluding the header, not a physical text line number.

## Validation Rules
Trim field values. Whitespace-only values are missing. Keep trimmed original values in reports. Compare IDs, emails, departments, employment types, and job-title matches case-insensitively. Use canonical configuration spelling for valid departments and types in processed results.

1. Check every required field. Reason: `Missing required field: <Field>`.
2. Nonblank department must occur in AllowedDepartments. Reason: `Unknown department: <value>`.
3. Nonblank employment type must occur in AllowedEmploymentTypes. Reason: `Unsupported employment type: <value>`.
4. Check nonblank email with the simple pattern `^[^\s@]+@[^\s@]+\.[^\s@]+$`. Reason: `Invalid email address`. This does not verify deliverability or restrict domains.
5. Parse nonblank StartDate strictly as `yyyy-MM-dd` with invariant culture and reject impossible dates. Reason: `Invalid start date`.
6. Pre-count all nonblank trimmed IDs and emails across the entire file, including otherwise invalid records. Every record sharing a value fails. Reasons: `Duplicate EmployeeID` and `Duplicate email address`. Never choose the first occurrence as the winner.
7. For an otherwise valid record, require a department rule with a nonempty group list. Reason: `Missing access rule for department: <department>`.

Collect all applicable reasons in the order above; required-field reasons follow the input column order listed above. Skip format and lookup checks on missing values to avoid redundant errors. Any reason means Status = Exception, AssignedGroups = empty array, and AppliedRules = empty array. Otherwise Status = Ready for Provisioning. No partial assignments are allowed.

## Access Rules
Validate configuration before processing: SchemaVersion must be 1; RuleSetVersion must be nonempty; allowed-value arrays and BaseGroups must be nonempty arrays of unique nonblank strings; DepartmentRules must be an object; JobTitleRules must be an array of objects with Department, JobTitle, and a nonempty Groups array. All group arrays contain nonblank strings. Reject department keys or title-rule departments outside AllowedDepartments, case-insensitive duplicate keys, and duplicate department/title pairs as configuration errors.

A missing allowed department entry is a record-level lookup exception, not a global failure. An existing malformed department entry is a configuration error. This distinction permits testing a missing rule while unrelated departments still process.

For a valid record, combine BaseGroups, DepartmentRules[Department], and the matching JobTitleRules entry for both Department and JobTitle. No title match means base plus department access, not an exception. Deduplicate groups case-insensitively while preserving base, department, then title order. A title from another department never matches. Do not infer privileged access from an IT department or title.

Record each applied rule as an object with RuleType (Base, Department, or JobTitle), RuleKey (BaseGroups, department name, or department + slash + title), and Groups. Preserve this explanation alongside final groups.

## Outputs
Each file contains one result per input record in source order. Add SourceRow to all results so missing or duplicate identifiers remain traceable. Overwrite the three reports on each successful run; do not append. UTF-8 output is required.

| File | Fields or content |
| --- | --- |
| `output/ProvisioningPlan.csv` | SourceRow, EmployeeID, EmployeeName, Email, Department, JobTitle, AssignedGroups, Status, ExceptionReason, ProcessedAt |
| `output/AuditLog.json` | JSON array of objects: RunId, Timestamp, SourceRow, EmployeeID, EmployeeName, Email, Department, JobTitle, Status, AssignedGroups, ExceptionReason, AppliedRules, RuleSetVersion, ConfigSha256 |
| `output/OnboardingSummary.html` | Employee Onboarding Summary; run ID and UTC time; Records Processed, Ready for Provisioning, Exceptions, Exception Rate; table with Source Row, Employee, Department, Job Title, Status, Details |

EmployeeName joins available trimmed first and last names with one space. AssignedGroups is a semicolon-separated string in CSV, an array in JSON. ExceptionReason joins ordered reasons with `; ` in both outputs and is an empty string on success. AppliedRules is a JSON array. ProcessedAt and Timestamp share the per-record UTC ISO 8601 timestamp. RunId is one GUID per invocation; ConfigSha256 is the SHA-256 hash of the loaded configuration bytes.

HTML Details shows groups on success and reasons on exceptions. HTML-encode every dynamic value. Exception Rate = Exceptions / Records Processed × 100, displayed to one decimal place. Summary totals must reconcile with both exported files.

## Error Handling
File or configuration syntax/schema failures stop the run before records are processed, with a clear terminal error and exit code 1. Leave existing reports untouched. A record-level unexpected error produces Exception with reason `Processing error`, no groups, and processing continues. Avoid exposing stack traces or machine paths in employee reports.

Write reports to temporary files first, then replace their final names only once all three serialize successfully. If writing or replacement fails, return exit code 1 and clearly state that reports may be stale or incomplete; do not claim a successful batch. Full cross-file atomicity is outside scope. For completed reports return 0 when all records are ready, or 2 when any record is an exception. Print the run ID, totals, and output paths so the user can identify the current run.

## Audit and Security
Keep all results, specific reasons, applied-rule group lists, rule version, and configuration hash. This is a per-run review log, not a tamper-proof audit system. Reports are overwritten; archive them separately if history is needed. Never store passwords, tokens, or real employee records in this repository. Never evaluate input as code. Escape HTML and protect CSV cells beginning with =, +, -, or @ by prefixing an apostrophe at export time; keep original trimmed values in JSON.
