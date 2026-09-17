# Test Cases

These acceptance tests cover the completed script. SourceRow counts employee records starting at 1, excluding the header. Run modified-input tests on temporary copies so the supplied data and rules stay unchanged.

## Verified Results

Testing on September 17, 2026 (UTC) confirmed 40 processed records, 30 Ready for Provisioning, 10 Exceptions, and exit code 2. All exception reasons below matched, including both members of duplicate pairs. TC01-TC16 passed in Windows PowerShell 5.1.26100.9444. Direct execution also passed in PowerShell 7.6.5.

TC17 passed for repeat runs, path handling, output directory creation, JSON parsing, CSV re-import, spreadsheet formula protection, and HTML totals and escaping. Screenshots of the rendered report were also visually reviewed: the summary, successful records, and all ten exception rows were readable and matched the expected results.

Additional checks passed for blank records, reordered and extra headers, zero- and one-element JSON arrays, case-insensitive group deduplication, malformed configuration, and output replacement failures. The injected row 2 error in TC13 produced 29 ready records and 11 exceptions; the remaining records still processed.

## Supplied Data

Expected baseline: 40 processed, 30 Ready for Provisioning, 10 Exceptions, 25.0% exception rate. Every exception has no assigned groups or applied rules. Rows 1–30 are valid.

| SourceRow | Employee | Expected reasons, in order |
| --- | --- | --- |
| 31 | Avery Spencer | Missing required field: Email |
| 32 | Nolan Rhodes | Missing required field: Manager |
| 33 | Kiara Sutton | Missing required field: JobTitle |
| 34 | Elise Abbott | Unknown department: Marketing |
| 35 | Mateo Delgado | Duplicate email address |
| 36 | Paige Henson | Duplicate email address |
| 37 | Roman Blake | Missing required field: EmployeeID; Missing required field: StartDate |
| 38 | Jasmine Holt | Invalid email address |
| 39 | Theo Walsh (first name blank in CSV) | Missing required field: FirstName; Unsupported employment type: Temporary; Duplicate EmployeeID |
| 40 | Sabrina Costa | Invalid start date; Duplicate EmployeeID |

Rows 35 and 36 share mateo.delgado@example.com. Rows 39 and 40 share E1079. Both members of each pair must fail. Row 37 has two missing fields. Row 39 has a whitespace-only FirstName.

## Test Cases

| Test ID | Scenario | Input Condition | Expected Result |
| --- | --- | --- | --- |
| TC01 | Valid Finance employee | SourceRow 1, Amara Wallace, Financial Analyst | Ready; basic package + Finance-Users, Finance-Shared, ERP-Finance-Read, Financial-Reporting. |
| TC02 | Valid IT employee | SourceRow 2, Ethan Navarro, IT Support Analyst | Ready; basic package + IT-Users, ServiceDesk-Portal, IT-KnowledgeBase, ServiceDesk-Analysts; no administrator groups. |
| TC03 | Valid Data Analyst | SourceRow 7, Nina Desai | Ready; basic package + Analytics-Users, Reporting-Workspace, BI-Reporting. |
| TC04 | Missing required values | Rows 31, 32, 33, 37, and 39 | Exceptions with the exact reasons above; whitespace-only FirstName counts as missing. |
| TC05 | Invalid department | SourceRow 34, Marketing | Exception: Unknown department: Marketing. |
| TC06 | Duplicate email | Rows 35 and 36 share email | Both Exception: Duplicate email address. Repeat on a copy with uppercase and surrounding spaces in one email; outcome stays the same. |
| TC07 | Duplicate EmployeeID | Rows 39 and 40 share E1079 | Both include Duplicate EmployeeID alongside their other reasons. |
| TC08 | Invalid or missing date | Row 40 has 2026-02-30; row 37 has no date | Row 40 includes Invalid start date; row 37 includes Missing required field: StartDate. On a copy, 10/05/2026 must also fail. |
| TC09 | Unsupported employment type | Row 39 has Temporary | Includes Unsupported employment type: Temporary. |
| TC10 | Missing configuration rule | On a config copy, remove DepartmentRules.Finance but retain Finance in AllowedDepartments | Otherwise valid Finance rows 1, 8, 15, 22, 29 become Exception: Missing access rule for department: Finance. Totals: 25 ready, 15 exceptions; other departments continue. |
| TC11 | Valid contract and remote staff | SourceRow 3 is Contract; SourceRow 4 is Remote | Both Ready; no employment-type or location restriction changes their groups. |
| TC12 | Multiple invalid records | Run the supplied file unchanged | 40 results in each report, 30 ready and 10 exceptions. Run returns exit code 2. |
| TC13 | Unexpected processing error | During testing, inject a throw inside row 2 processing through a test harness; remove injection afterward | Row 2 becomes Processing error with no groups. Rows 3–40 still process; 29 ready, 11 exceptions. |
| TC14 | Malformed email | SourceRow 38 lacks @ | Exception: Invalid email address. |
| TC15 | Input and configuration failures | Separate temporary tests: missing CSV, missing Email header, duplicate header, broken CSV quoting, header-only CSV, invalid JSON, or BaseGroups set to a string | Exit 1 before row processing; clear error and previous reports left untouched. |
| TC16 | Title matching and normalization | Row 9 is Systems Analyst; on copies add spaces/case changes to valid values, then change row 1 title to IT Support Analyst | Row 9 gets base + IT department groups only. Spaces/case do not change matching. Changed row 1 gets base + Finance groups only, never ServiceDesk-Analysts. |
| TC17 | Reports and repeat runs | Run baseline twice, then invoke from another working directory with absolute script and CSV paths; also test a writable output folder missing initially | Output directory is created; reports replace prior runs with no accumulation; IDs/timestamps identify each run. Parse JSON, re-import CSV, open HTML in a browser, check totals and encoded text. Use temporary special-character field values to check HTML escaping and spreadsheet formula protection. |

The basic package is Standard-Users, Employee-Portal, and Microsoft-365-Standard. For each ready record, confirm audit AppliedRules explains every assigned group. The sample reports in `output/` were generated by running the script against the supplied synthetic dataset.
