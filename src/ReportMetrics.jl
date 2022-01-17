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
    )

Reports allocations
 - `job_name` name of job
 - `run_cmd` a `Base.Cmd` to run script
 - `deps_to_monitor` a `Vector` of modules to monitor
 - `dirs_to_monitor` a `Vector` of directories to monitor
 - `pkg_name` name of package being tested (for helping with string processing)
 - `n_unique_allocs` limits number of unique allocation sites to report (to avoid large tables)
 - `suppress_url` (` = true`) suppress trying to use URLs in the output table

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

    case_bytes = reverse(getproperty.(allocs, :bytes))
    case_filename = reverse(getproperty.(allocs, :filename))
    case_linenumber = reverse(getproperty.(allocs, :linenumber))
    process_fn(fn) = post_process_fn(process_filename(fn))

    all_bytes = Int[]
    filenames = String[]
    linenumbers = Int[]
    loc_ids = String[]
    for (bytes, filename, linenumber) in zip(case_bytes, case_filename, case_linenumber)
        is_loading_pkg(filename, linenumber) && continue # Try to skip loading module if pkg_name is included
        loc_id = "$(process_fn(filename)):$(linenumber)"
        if !(bytes in all_bytes) && !(loc_id in loc_ids)
            push!(all_bytes, bytes)
            push!(filenames, filename)
            push!(linenumbers, linenumber)
            push!(loc_ids, loc_id)
            if length(all_bytes) ≥ n_unique_allocs
                break
            end
        end
    end
    @info "$(job_name): Number of unique allocating sites: $(length(all_bytes))"
    sum_bytes = sum(all_bytes)
    xtick_name(filename, linenumber) = "$filename:$linenumber"
    labels = xtick_name.(process_fn.(filenames), linenumbers)

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

    data = map(zip(filenames, linenumbers)) do (filename, linenumber)
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

    alloc_percent = map(all_bytes) do bytes
        alloc_perc = bytes / sum_bytes
        Int(round(alloc_perc*100, digits = 0))
    end
    header = (
        ["Allocations %", "Allocations", "<file>:<line number>"],
        ["(xᵢ/∑x)", "(bytes)", ""],
    )

    table_data = hcat(
        alloc_percent,
        all_bytes,
        data,
    )

    PrettyTables.pretty_table(
        table_data;
        header,
        formatters = PrettyTables.ft_printf("%s", 2:2),
        header_crayon = PrettyTables.crayon"yellow bold",
        subheader_crayon = PrettyTables.crayon"green bold",
        crop = :none,
    )
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

end # module
