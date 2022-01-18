import ReportMetrics
using Test

ma_dir = ReportMetrics.mod_dir(ReportMetrics)

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
end
