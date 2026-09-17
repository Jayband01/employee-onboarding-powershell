# Process Flow

## Main Process
Use these labels when recreating the flow in Visio. Rectangles are actions, diamonds are decisions, and rounded shapes mark the start and end.

| Step | Shape | Label | Next |
| --- | --- | --- | --- |
| 1 | Start | HR Intake File | 2 |
| 2 | Action | File Validation | 3 |
| 3 | Decision | File and configuration usable? | Yes: 4. No: display batch error and end. |
| 4 | Action | Import records and count duplicate IDs and emails | 5 |
| 5 | Action | Employee Record Validation | 6 |
| 6 | Decision | Record valid? | Yes: 7. No: 10. |
| 7 | Action | Access Rule Lookup | 8 |
| 8 | Decision | Required department rule found? | Yes: 9. No: 10. |
| 9 | Action | Provisioning Plan Creation | Set Ready for Provisioning; then 11. |
| 10 | Action | Record Exception | Clear groups; collect reasons; then 11. |
| 11 | Action | Audit Logging | Store result and rule explanation in memory; then 12. |
| 12 | Decision | More employee records? | Yes: 5. No: 13. |
| 13 | Action | Summary Reporting | Serialize CSV, JSON, and HTML; then 14. |
| 14 | End | Report run status | Print counts and output paths. |

## Exception Branch
Employee Record Validation leads to Invalid Record, then Record Exception, then Audit Logging. The More employee records? decision returns to validation for the next employee. A bad employee record does not end the batch.

Any unexpected error during validation, lookup, or plan creation follows Record Exception with reason Processing error. Report-writing failures end the batch with a terminal error. Audit Logging collects per-record results; AuditLog.json is exported after all records are processed.
