# Windows memory measurements

`measure-desktop.py` and `measure-agent.py` record distinct native counters:

| JSON field | Meaning |
| --- | --- |
| `working_set_mib` | Resident pages, including pages shareable with other processes |
| `private_commit_mib` | Private committed address space; some pages may not be resident |
| `private_mib` | Retained compatibility alias for `private_commit_mib` |
| `private_working_set_mib` | Resident private pages, when Windows provides this counter |
| `shared_commit_mib` | Shared committed memory, when Windows provides this counter |

The reader uses [PROCESS_MEMORY_COUNTERS_EX2](https://learn.microsoft.com/windows/win32/api/psapi/ns-psapi-process_memory_counters_ex2).
Older systems that provide only the EX prefix return `null` for the two extra
counters and identify the format in `memory_counter_format`. An access failure
fails the sample instead of reporting zero. These fields neither measure GPU
memory nor deduplicate shared pages across a process family.

Run `python windows/test-process-memory.py` from PowerShell to test an owned
16 MiB allocation and its release, invalid handles and older counter formats.
It opens no window and changes no process working-set limit. Linux runs the
structure checks and explicitly skips the native Windows cases.

The counters distinguish a resident-memory increase from private commit in
future recordings. They do not explain the previously observed long-run
resident-memory outlier by themselves. Whole-Marea sustained measurements and
their rendering/input checks remain necessary; no RAM reduction is claimed by
this diagnostic change.
