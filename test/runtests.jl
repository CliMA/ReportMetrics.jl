import ReportAllocations
using Test

ma_dir = ReportAllocations.mod_dir(ReportAllocations)

@testset "ReportAllocations" begin
    ReportAllocations.report_allocs(;
        job_name = "RA_example",
        filename = joinpath(ma_dir, "test", "rep_workload.jl"), # requires use of Profile.jl
        deps_to_monitor = [ReportAllocations],
        dirs_to_monitor = [joinpath(ma_dir, "test")],
        n_unique_allocs = 10,
    )
end
