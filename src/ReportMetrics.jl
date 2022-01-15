module ReportMetrics

import Pkg
import PrettyTables
import Coverage

mod_dir(x) = dirname(dirname(pathof(x)))

"""
    report_allocs(;
        job_name::String,
        run_cmd::String = "",
        filename::String = "",
        deps_to_monitor::Vector{Module} = Module[],
        dirs_to_monitor::Vector{String} = String[],
        splitbys::Vector{String} = String[],
        pkg_name::Union{Nothing, String} = nothing,
        n_unique_allocs::Int = 10,
    )

Reports allocations
 - `job_name` name of job
 - `run_cmd` command to run script (alternatively use `filename`)
 - `filename` file to run (alternatively use `run_cmd`)
 - `deps_to_monitor` a `Vector` of modules to monitor
 - `dirs_to_monitor` a `Vector` of directories to monitor
 - `splitbys` a `Vector` of `String`s used to split / process names
 - `pkg_name` name of package being tested (tries to skip allocations related to loading the module)
 - `n_unique_allocs` limits number of unique allocation sites to report (to avoid large tables)

## Notest
 - `deps_to_monitor` and `dirs_to_monitor` are merged together.
"""
function report_allocs(;
        job_name::String,
        run_cmd::String = "",
        filename::String = "",
        deps_to_monitor::Vector{Module} = Module[],
        dirs_to_monitor::Vector{String} = String[],
        splitbys::Vector{String} = String[],
        pkg_name::Union{Nothing, String} = nothing,
        n_unique_allocs::Int = 10,
    )

    ##### Collect deps
    dep_dirs = map(deps_to_monitor) do dep
        mod_dir(dep)
    end
    all_dirs_to_monitor = [dirs_to_monitor..., dep_dirs...]

    ##### Run representative work & track allocations
    if filename ≠ ""
        @assert isfile(filename)
        run(`$(Base.julia_cmd()) --project --track-allocation=all $filename`)
    else
        run(`$run_cmd`)
    end
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

    filter!(x -> x.bytes ≠ 0, allocs)
    filter!(x -> !compile_pkg(x.filename, x.linenumber), allocs) # Try to skip loading module if pkg_name is included

    n_alloc_sites = length(allocs)
    if n_alloc_sites == 0
        @info "$(job_name): Number of sampled allocating sites: $n_alloc_sites 🎉"
        return
    end

    case_bytes = reverse(getproperty.(allocs, :bytes))
    case_filename = reverse(getproperty.(allocs, :filename))
    case_linenumber = reverse(getproperty.(allocs, :linenumber))

    all_bytes = Int[]
    filenames = String[]
    linenumbers = Int[]
    loc_ids = String[]
    for (bytes, filename, linenumber) in zip(case_bytes, case_filename, case_linenumber)
        compile_pkg(filename, linenumber) && continue # Try to skip loading module if pkg_name is included
        loc_id = "$(filename_only(filename)):$(linenumber)"
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
    all_kbytes = map(b -> div(b, 1024), all_bytes) # convert from bytes to KiB
    sum_bytes = sum(all_kbytes)
    xtick_name(filename, linenumber) = "$filename:$linenumber"
    labels = xtick_name.(filename_only.(filenames), linenumbers)

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
        label = xtick_name(filename_only(filename), linenumber)
        name = basename(pkg_dir_from_file(dirname(filename)))
        url = ""
        # TODO: incorporate URLS into table
        # if haskey(pkg_urls, name)
        #     url = pkg_urls[name]
        # else
        #     url = "https://www.google.com"
        # end
        PrettyTables.URLTextCell(label, url)
    end

    alloc_percent = map(all_kbytes) do bytes
        alloc_percent = bytes / sum_bytes
        Int(round(alloc_percent*100, digits = 0))
    end
    header = (
        ["Allocations %", "Allocations", "<file>:<line number>"],
        ["(alloc_i/∑allocs)", "(KiB)", ""],
    )

    table_data = hcat(
        alloc_percent,
        all_kbytes,
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
