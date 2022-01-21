module ReportMetrics

import Pkg
import PrettyTables
import Coverage

mod_dir(x) = dirname(dirname(pathof(x)))

"""
    report_allocs(;
        job_name::String,
        run_cmd::String = "",
        deps_to_monitor::Vector{Module} = Module[],
        dirs_to_monitor::Vector{String} = String[],
        pkg_name::Union{Nothing, String} = nothing,
        n_unique_allocs::Int = 10,
        write_csv::Bool = false,
        csv_prefix_path::String = "",
    )

Reports allocations
 - `job_name` name of job
 - `run_cmd` a `Base.Cmd` to run script
 - `deps_to_monitor` a `Vector` of modules to monitor
 - `dirs_to_monitor` a `Vector` of directories to monitor
 - `pkg_name` name of package being tested (for helping with string processing)
 - `n_unique_allocs` limits number of unique allocation sites to report (to avoid large tables)
 - `suppress_url` (` = true`) suppress trying to use URLs in the output table
 - `write_csv` Bool to write a csv output
 - `csv_prefix_path` prefix path to write the csv file

## Notest
 - `deps_to_monitor` and `dirs_to_monitor` are merged together.
"""
function report_allocs(;
        job_name::String,
        run_cmd::Union{Nothing, Base.Cmd} = nothing,
        deps_to_monitor::Vector{Module} = Module[],
        dirs_to_monitor::Vector{String} = String[],
        process_filename::Function = process_filename_default,
        is_loading_pkg::Function = (fn, ln) -> false,
        pkg_name::Union{Nothing, String} = nothing,
        n_unique_allocs::Int = 10,
        suppress_url::Bool = true,
        write_csv::Bool = false,
        csv_prefix_path::String = "",
        format_locid::Function = x -> x,
    )

    ##### Collect deps
    dep_dirs = map(deps_to_monitor) do dep
        mod_dir(dep)
    end
    all_dirs_to_monitor = [dirs_to_monitor..., dep_dirs...]

    ##### Run representative work & track allocations
    run(run_cmd)
    allocs = Coverage.analyze_malloc(all_dirs_to_monitor)

    ##### Clean up files
    for d in all_dirs_to_monitor
        all_files = [
            joinpath(root, f) for
            (root, dirs, files) in Base.Filesystem.walkdir(d) for f in files
        ]
        all_mem_files = filter(x -> endswith(x, ".mem"), all_files)
        for f in all_mem_files
            rm(f)
        end
    end

    ##### Process and plot results
    filter!(x -> x.bytes ≠ 0, allocs)
    filter!(x -> !is_loading_pkg(x.filename, x.linenumber), allocs) # Try to skip loading module if pkg_name is included

    n_alloc_sites = length(allocs)
    if n_alloc_sites == 0
        @info "$(job_name): Number of sampled allocating sites: $n_alloc_sites 🎉"
        return
    end

    all_bytes = reverse(getproperty.(allocs, :bytes))
    all_filenames = reverse(getproperty.(allocs, :filename))
    all_linenumbers = reverse(getproperty.(allocs, :linenumber))
    process_fn(fn) = post_process_fn(process_filename(fn))

    bytes_subset = Int[]
    filenames_subset = String[]
    linenumbers_subset = Int[]
    loc_ids_subset = String[]
    truncated_allocs = false
    for (bytes, filename, linenumber) in zip(all_bytes, all_filenames, all_linenumbers)
        is_loading_pkg(filename, linenumber) && continue # Try to skip loading module if pkg_name is included
        loc_id = "$(process_fn(filename)):$(linenumber)"
        if !(bytes in bytes_subset) && !(loc_id in loc_ids_subset)
            push!(bytes_subset, bytes)
            push!(filenames_subset, filename)
            push!(linenumbers_subset, linenumber)
            push!(loc_ids_subset, loc_id)
            if length(bytes_subset) ≥ n_unique_allocs
                truncated_allocs = true
                break
            end
        end
    end
    sum_bytes = sum(bytes_subset)
    trunc_msg = truncated_allocs ? " (truncated) " : ""
    @info "$(job_name): $(length(bytes_subset)) unique allocating sites, $sum_bytes total bytes$trunc_msg"
    xtick_name(filename, linenumber) = "$filename:$linenumber"
    labels = xtick_name.(process_fn.(filenames_subset), linenumbers_subset)

    # TODO: get urls for hypertext
    pkg_urls = Dict(map(all_dirs_to_monitor) do dep_dir
        proj = Pkg.Types.read_project(joinpath(dep_dir, "Project.toml"))
        if proj.uuid ≠ nothing
            url = Pkg.Operations.find_urls(Pkg.Types.Context().registries, proj.uuid)
            Pair(proj.name, url)
        else
            Pair(proj.name, "https://www.google.com")
        end
    end...)

    fileinfo = map(zip(filenames_subset, linenumbers_subset)) do (filename, linenumber)
        label = xtick_name(process_fn(filename), linenumber)
        if suppress_url
            label
        else
            url = ""
            # name = basename(pkg_dir_from_file(dirname(filename)))
            # TODO: incorporate URLS into table
            # if haskey(pkg_urls, name)
            #     url = pkg_urls[name]
            # else
            #     url = "https://www.google.com"
            # end
            PrettyTables.URLTextCell(label, url)
        end
    end

    alloc_percent = map(bytes_subset) do bytes
        alloc_perc = bytes / sum_bytes
        Int(round(alloc_perc*100, digits = 0))
    end
    header = (
        ["<file>:<line number>", "Allocations", "Allocations %"],
        ["", "(bytes)", "(xᵢ/∑x)"],
    )

    table_data = hcat(
        fileinfo,
        bytes_subset,
        alloc_percent,
    )

    PrettyTables.pretty_table(
        table_data;
        header,
        formatters = PrettyTables.ft_printf("%s", 2:2),
        header_crayon = PrettyTables.crayon"yellow bold",
        subheader_crayon = PrettyTables.crayon"green bold",
        crop = :none,
        alignment = [:l, :c, :c],
    )
    if write_csv
        mkpath(csv_prefix_path)
        open(joinpath(csv_prefix_path, "$job_name" * ".csv"), "w") do fh
            for (bytes, loc) in zip(bytes_subset, loc_ids_subset)
                println(fh, "$bytes\t|\t$(format_locid(loc))")
                # println(fh, "$bytes,$loc")
            end
        end
    end
end

# Try to find a package directory from a file
function pkg_dir_from_file(filename, candidates = String[])
    _pkg_dir_from_file!(dirname(filename), candidates)
    if length(candidates) > 1
        @debug "Multiple Project.toml files found recursively through $filename.\n$(first(candidates)) used."
    end
    return first(candidates)
end

function _pkg_dir_from_file!(dir, candidates)
    @assert ispath(dir)
    if isfile(joinpath(dir, "Project.toml"))
        push!(candidates, dir)
        _pkg_dir_from_file!(dirname(dir), candidates)
    end
end

function post_process_fn(fn)
    # Remove ###.mem.
    fn = join(split(fn, ".jl")[1:(end - 1)], ".jl") * ".jl"
    if startswith(fn, Base.Filesystem.path_separator)
        fn = fn[2:end]
    end
    return fn
end

function process_filename_default(fn)
    # TODO: make this work for Windows
    if occursin(".julia/packages/", fn)
        fn = last(split(fn, ".julia/packages/"))
        pkg_name = first(split(fn, "/"))
        if occursin("$pkg_name/src", fn)
            return fn
        else
            fn = join(split(fn, pkg_name)[2:end], pkg_name)
            sha = split(fn, "/")[2]
            fn = replace(fn, sha*"/" => "")
            fn = pkg_name*fn
            return fn
        end
    end
    return fn
end

#=
# name helper functions
function filename_only(fn)
    if occursin(".jl", fn)
        fn = join(split(fn, ".jl")[1:(end - 1)], ".jl") * ".jl"
    end
    fn = replace(fn, "\\" => "/") # for windows...
    isempty(deps_to_monitor) && return fn

    for dep_name in string.(deps_to_monitor)
        if occursin(dep_name, fn)
            fn = dep_name * last(split(fn, dep_name))
        end
    end
    isempty(splitbys) && return fn
    for splitby in splitbys
        if occursin(splitby, fn)
            fn = splitby * last(split(fn, splitby))
        end
    end
    return fn
end
function compile_pkg(fn, linenumber)
    c1 = if pkg_name ≠ nothing
        endswith(filename_only(fn), pkg_name)
    else
        false
    end
    c2 = linenumber == 1
    return c1 && c2
end
=#

#=
For integrating with buildkite

function format_locid(locid)
    relpth, lineno = split(locid, ':')
    if haskey(ENV, "BUILDKITE") && ENV["BUILDKITE"] == "true"
        return join(
            [PKG_ORG, PKG_NAME, "blob", ENV["BUILDKITE_COMMIT"], relpth],
            '/',
        ) * "#$(lineno)"
    end
    return join([PKG_NAME, locid], '/')
end
=#

import SnoopCompile

"""
    report_invalidations(;
        job_name::String,
        invalidations,
        process_filename::Function = x -> x,
        write_csv::Bool = false,
        csv_prefix_path::String = "",
        format_locid::Function = x -> x,
    )

Report a table of invalidations.

For documentation, see https://timholy.github.io/SnoopCompile.jl/stable/snoopr/

## Usage example
```julia
import SnoopCompileCore
invalidations = SnoopCompileCore.@snoopr begin

    # load packages & do representative work

end;
import ReportMetrics
ReportMetrics.report_invalidations(;
    job_name = "MyWork",
    invalidations,
    process_filename = x -> last(split(x, "packages/")),
)
```
"""
function report_invalidations(;
        job_name::String,
        invalidations,
        process_filename::Function = x -> x,
        write_csv::Bool = false,
        csv_prefix_path::String = "",
        format_locid::Function = x -> x,
    )

    trees = reverse(SnoopCompile.invalidation_trees(invalidations))

    n_total_invalidations = length(SnoopCompile.uinvalidated(invalidations))
    @info "Number of invalidations for $job_name: $n_total_invalidations"

    invs_per_method = map(trees) do methinvs
        SnoopCompile.countchildren(methinvs)
    end
    sum_invs = sum(invs_per_method)

    n_invalidations_percent = map(invs_per_method) do inv
        inv_perc = inv / sum_invs
        Int(round(inv_perc*100, digits = 0))
    end
    meth_name = map(trees) do inv
        "$(inv.method.name)"
    end
    fileinfo = map(trees) do inv
        "$(process_filename(string(inv.method.file))):$(inv.method.line)"
    end

    header = (
        ["<file name>:<line number>", "Method Name", "Invalidations", "Invalidations %"],
        ["", "", "Number", "(xᵢ/∑x)"],
    )

    table_data = hcat(
        fileinfo,
        meth_name,
        invs_per_method,
        n_invalidations_percent,
    )

    PrettyTables.pretty_table(
        table_data;
        header,
        formatters = PrettyTables.ft_printf("%s", 2:2),
        header_crayon = PrettyTables.crayon"yellow bold",
        subheader_crayon = PrettyTables.crayon"green bold",
        crop = :none,
        alignment = [:l, :c, :c, :c],
    )
    if write_csv
        mkpath(csv_prefix_path)
        open(joinpath(csv_prefix_path, "$job_name" * ".csv"), "w") do fh
            for (name, finfo, inv) in zip(meth_name, fileinfo, invs_per_method)
                println(fh, "$(format_locid(finfo))\t|\t$name\t|\t$inv")
            end
        end
    end

end

end # module
