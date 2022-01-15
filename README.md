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


A package for reporting allocations, which builds ontop of [Coverage.jl](https://github.com/JuliaCI/Coverage.jl)

## Example

See our test suite for an example usage:

```julia
import ReportMetrics
ReportMetrics.report_allocs(;
    job_name = "RA_example",
    filename = joinpath(ma_dir, "test", "rep_workload.jl"), # requires use of Profile.jl
    dirs_to_monitor = [joinpath(ma_dir, "test")],
)
```

prints out:

```julia
[ Info: RA_example: Number of unique allocating sites: 2
┌───────────────────┬─────────────┬─────────────────────────────────────────────┐
│     Allocations % │ Allocations │                        <file>:<line number> │
│ (alloc_i/∑allocs) │       (KiB) │                                             │
├───────────────────┼─────────────┼─────────────────────────────────────────────┤
│          0.606143 │      468718 │ ReportMetrics.jl/test/rep_workload.jl:9 │
│          0.393857 │      304562 │ ReportMetrics.jl/test/rep_workload.jl:8 │
└───────────────────┴─────────────┴─────────────────────────────────────────────┘
```
