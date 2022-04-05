#####
##### Invalidations (needed first due to package loading effects)
#####

import SnoopCompileCore
invalidations = SnoopCompileCore.@snoopr begin

    include("rep_workload.jl") # change to `include("test/rep_workload.jl")` for local run

end;

if !("." in LOAD_PATH)
    push!(LOAD_PATH, ".")
end
import ReportMetrics
ReportMetrics.report_invalidations(;
    job_name = "RA_example_inv",
    invalidations,
    process_filename = x -> last(split(x, "packages/")),
)
ReportMetrics.report_invalidations(;
    job_name = "RA_example_inv",
    invalidations,
    process_filename = x -> last(split(x, "packages/")),
    n_rows = 3,
)

using Test

ma_dir = pkgdir(ReportMetrics)

@testset "ReportMetrics" begin
    ReportMetrics.report_allocs(;
        job_name = "RA_example",
        run_cmd = `$(Base.julia_cmd()) --project --track-allocation=all $(joinpath(ma_dir, "test", "rep_workload.jl"))`,
        deps_to_monitor = [ReportMetrics],
        dirs_to_monitor = [joinpath(ma_dir, "test")],
        process_filename = x -> replace(x, dirname(ma_dir) => ""),
    )

    ReportMetrics.report_allocs(;
        job_name = "RA_example_csv",
        run_cmd = `$(Base.julia_cmd()) --project --track-allocation=all $(joinpath(ma_dir, "test", "rep_workload.jl"))`,
        deps_to_monitor = [ReportMetrics],
        dirs_to_monitor = [joinpath(ma_dir, "test")],
        process_filename = x -> replace(x, dirname(ma_dir) => ""),
        write_csv = true,
    )

    ReportMetrics.report_allocs(;
        job_name = "RA_example",
        run_cmd = `$(Base.julia_cmd()) --project --track-allocation=all $(joinpath(ma_dir, "test", "rep_workload.jl"))`,
        deps_to_monitor = [ReportMetrics],
        dirs_to_monitor = [joinpath(ma_dir, "test")],
        process_filename = x -> replace(x, dirname(ma_dir) => ""),
        n_unique_allocs = 1,
    )
end
