import ReportMetrics
import SpecialFunctions
using Test

ma_dir = ReportMetrics.mod_dir(ReportMetrics)

@testset "ReportMetrics" begin
    ReportMetrics.report_allocs(;
        job_name = "RA_example",
        filename = joinpath(ma_dir, "test", "rep_workload.jl"), # requires use of Profile.jl
        deps_to_monitor = [ReportMetrics, SpecialFunctions],
        dirs_to_monitor = [joinpath(ma_dir, "test")],
        n_unique_allocs = 10,
    )
end
