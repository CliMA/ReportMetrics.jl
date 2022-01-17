# ReportMetrics.jl #

|||
|---------------------:|:----------------------------------------------|
| **GHA CI**           | [![gha ci][gha-ci-img]][gha-ci-url]           |
| **Code Coverage**    | [![codecov][codecov-img]][codecov-url]        |
| **Bors enabled**     | [![bors][bors-img]][bors-url]                 |

[gha-ci-img]: https://github.com/CliMA/ReportMetrics.jl/actions/workflows/ci.yml/badge.svg
[gha-ci-url]: https://github.com/CliMA/ReportMetrics.jl/actions/workflows/ci.yml

[codecov-img]: https://codecov.io/gh/CliMA/ReportMetrics.jl/branch/main/graph/badge.svg
[codecov-url]: https://codecov.io/gh/CliMA/ReportMetrics.jl

[bors-img]: https://bors.tech/images/badge_small.svg
[bors-url]: https://app.bors.tech/repositories/41363


A package for reporting metrics (e.g., allocations), which builds ontop of [Coverage.jl](https://github.com/JuliaCI/Coverage.jl)

## Example

See our test suite for an example usage:

```julia
import ReportMetrics
ma_dir = ReportMetrics.mod_dir(ReportMetrics)
ReportMetrics.report_allocs(;
    job_name = "RA_example",
    run_cmd = `$(Base.julia_cmd()) --project --track-allocation=all $(joinpath(ma_dir, "test", "rep_workload.jl"))`,
    deps_to_monitor = [ReportMetrics],
    dirs_to_monitor = [joinpath(ma_dir, "test")],
    process_filename = x -> replace(x, dirname(ma_dir) => ""),
)
```

prints out:

```julia
[ Info: RA_example: Number of unique allocating sites: 2
┌───────────────────┬─────────────┬─────────────────────────────────────────┐
│     Allocations % │ Allocations │                    <file>:<line number> │
│ (alloc_i/∑allocs) │       (KiB) │                                         │
├───────────────────┼─────────────┼─────────────────────────────────────────┤
│                77 │        7809 │ ReportMetrics.jl/test/rep_workload.jl:7 │
│                23 │        2331 │ ReportMetrics.jl/test/rep_workload.jl:6 │
└───────────────────┴─────────────┴─────────────────────────────────────────┘
```
