# Employee Onboarding & Access Automation

I built this project to practice PowerShell with a common HR-to-IT workflow, checking new-hire records and working out which access each person would need. It gave me practice with CSV and JSON, validation, exception handling, and access rules.

Everything is fictional. The script creates a simulated provisioning plan; it does not create accounts or connect to Active Directory, Microsoft Entra ID, or any other service.

## How it works

HR intake CSV → validation → access rules → provisioning plan, audit log, and HTML summary

The script checks the file and configuration first, then processes each employee independently. Valid records become `Ready for Provisioning`. Invalid records become `Exception`, with specific reasons and no assigned groups. A failed record does not stop later records.

The [CSV](data/new_hires.csv) includes the kinds of formatting differences that can show up in an HR export: extra spaces, mixed department casing, and employment types such as `contract` and `part-time`. I added these after the first version to check the normalization with the supplied data, alongside the missing fields, malformed email, invalid date, and duplicate records already present.

## Validation and access rules

- Trim field values and treat whitespace-only fields as missing.
- Check required columns and fields, allowed departments and employment types, email format, and valid `yyyy-MM-dd` dates.
- Compare IDs, emails, departments, employment types, and titles without regard to case. Normalize recognized departments and employment types to the configuration's spelling.
- Flag every record sharing an ID or email, including the first occurrence and otherwise invalid records.

Access comes from [config/access_rules.json](config/access_rules.json): standard groups, department groups, then any matching department-and-title additions. Duplicate groups are removed while preserving that order. An unmatched title gets standard and department access; IT employment never implies administrator access.

Input or configuration errors leave previous reports untouched. Reports are serialized before replacement; an output failure warns that the files may be stale or incomplete. The exact validation order, configuration schema, and report fields are in [ProjectRequirements.md](docs/ProjectRequirements.md).

## Run it

From the repository root, using PowerShell 7:

```powershell
pwsh -NoProfile -File .\scripts\Invoke-EmployeeOnboarding.ps1 -CsvPath .\data\new_hires.csv
```

No administrator rights or extra modules are needed. The script does not change execution policy. A relative CSV path starts from your current directory; configuration and report paths start from the repository.

Reports go into `output/`, which is created if needed:

| File | Contents |
| --- | --- |
| [ProvisioningPlan.csv](output/ProvisioningPlan.csv) | Proposed groups, status, and reasons for every record |
| [AuditLog.json](output/AuditLog.json) | The same results, applied rules, UTC timestamps, run ID, and configuration hash |
| [OnboardingSummary.html](output/OnboardingSummary.html) | Batch totals and a readable employee table; download and open in a browser |

Exit codes: `0` means all records are ready, `2` means the batch completed with exceptions, and `1` means a file, configuration, or output failure. The supplied data intentionally returns `2`.

## Results and testing

The revised feed produced **40 records: 30 ready and 10 exceptions (25%)**. The counts stayed the same because the added spaces and casing differences are handled by normalization. The exception rate describes this test dataset, not a business outcome.

Regression checks covered the documented exception reasons, normalization, duplicate pairs, access assignments, missing configuration rules, and an injected record failure. JSON parsing, CSV re-import, HTML contents and escaping, output failures, path handling, and repeated runs also passed. Tests ran in Windows PowerShell 5.1 and PowerShell 7.6.5; PowerShell 7 direct execution passed.

[TestCases.md](docs/TestCases.md) records the scenarios, expected reasons, and results, including the formatting changes in the supplied feed.

## Sample report

![Employee Onboarding Summary showing 40 records, 30 ready, and 10 exceptions](screenshots/onboarding-summary.png)

![Exception rows with specific validation reasons](screenshots/onboarding-exceptions.png)

These screenshots are from an earlier run. The current feed produces the same displayed names, departments, titles, groups, and exceptions after normalization; run IDs and timestamps change on each run.

## Files

- [scripts/Invoke-EmployeeOnboarding.ps1](scripts/Invoke-EmployeeOnboarding.ps1) — the workflow
- [data/new_hires.csv](data/new_hires.csv) and [config/access_rules.json](config/access_rules.json) — fictional intake and access policy
- [docs/ProjectRequirements.md](docs/ProjectRequirements.md) and [docs/TestCases.md](docs/TestCases.md) — detailed rules and validation evidence
- `output/` and `screenshots/` — generated reports and report screenshots

## Limitations and next steps

This is a local simulation with fictional groups. Duplicate checks cover only the current batch. Manager identity, email ownership, and actual access are not verified. Reports replace the previous run; they are not a historical or tamper-proof audit store.

Next, I'd add dated run folders so earlier results are retained, then explore an approval step. Any future Active Directory or Microsoft Entra integration would be a separate, controlled lab exercise.
