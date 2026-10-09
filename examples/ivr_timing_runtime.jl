"""Read-only runtime inventory for the source-pinned timing worker.

No optimizer invocation. Package sources include extensions; selected installed
artifacts and actually loaded package caches/images are inventoried separately.
Apple shared-cache system libraries are identified by OS build, not byte hashes.
"""
module IVRTimingRuntime
using Pkg, TOML, SHA, Libdl, LinearAlgebra

hashfile(path)=bytes2hex(open(SHA.sha256,path))
const ENV_KEYS=("JULIA_DEPOT_PATH","JULIA_LOAD_PATH","JULIA_NUM_THREADS","JULIA_CPU_TARGET",
    "JULIA_BINDIR","JULIA_PROJECT","JULIA_PKG_OFFLINE","OPENBLAS_NUM_THREADS",
    "OMP_NUM_THREADS","VECLIB_MAXIMUM_THREADS","DYLD_LIBRARY_PATH","LD_LIBRARY_PATH")

function capture()
    files=Dict{String,String}();aliases=Dict{String,String}();trees=Dict{String,Vector{String}}()
    function file(path)
        raw=abspath(path);isfile(raw) || error("runtime file missing: $raw")
        resolved=realpath(raw);raw==resolved || (aliases[raw]=resolved)
        haskey(files,resolved) || (files[resolved]=hashfile(resolved))
        resolved
    end
    function tree(path)
        raw=abspath(path);root=realpath(raw);raw==root || (aliases[raw]=root)
        haskey(trees,root) && return root
        names=String[]
        for (dir,dirs,fs) in walkdir(root;follow_symlinks=false)
            filter!(d->d!=".git" && d!="__pycache__",dirs)
            for name in fs
                p=joinpath(dir,name)
                # Symlinked shared libraries are recorded along with their targets.
                isfile(p) || error("unreadable runtime tree member: $p")
                push!(names,relpath(p,root));file(p)
            end
            for name in dirs
                p=joinpath(dir,name)
                islink(p) && error("directory symlink needs explicit runtime review: $p")
            end
        end
        trees[root]=sort!(names);root
    end
    project=Base.active_project();project===nothing && error("explicit project required")
    file(project);file(joinpath(dirname(project),"Manifest.toml"))
    packages=Any[];artifacts=Dict{String,Any}();uninstalled=String[]
    for (uuid,info) in sort!(collect(Pkg.dependencies());by=x->string(first(x)))
        info.source===nothing && error("dependency source unavailable: $(info.name)")
        root=tree(info.source)
        push!(packages,Dict("uuid"=>string(uuid),"name"=>info.name,"version"=>string(info.version),"source"=>root))
        manifest=joinpath(root,"Artifacts.toml")
        isfile(manifest) || continue
        for name in sort!(collect(keys(TOML.parsefile(manifest))))
            meta=Pkg.Artifacts.artifact_meta(name,manifest)
            meta===nothing && continue # No binding for this host platform.
            hash=meta["git-tree-sha1"];path=Pkg.Artifacts.artifact_path(Base.SHA1(hash))
            if isdir(path)
                artifacts[hash]=Dict("root"=>tree(path),"host_selected"=>true)
            else
                push!(uninstalled,"$(info.name)/$name/$hash")
            end
        end
    end
    caches=Dict{String,Any}()
    isdefined(Base,:pkgorigins) || error("runtime lacks reviewed package-origin API")
    for (id,origin) in Base.pkgorigins
        hasproperty(origin,:cachepath) || error("unreviewed package cache metadata")
        origin.cachepath===nothing && continue
        cache=file(origin.cachepath)
        image=Base.ocachefile_from_cachefile(origin.cachepath)
        caches[string(id)]=Dict("cache"=>cache,"image"=>isfile(image) ? file(image) : nothing)
    end
    system=String[];libraries=String[]
    for path in sort!(unique(Libdl.dllist()))
        if isfile(path)
            push!(libraries,file(path))
        elseif Sys.isapple() && (startswith(path,"/usr/lib/") || startswith(path,"/System/Library/"))
            push!(system,path)
        else
            error("unresolved loaded library: $path")
        end
    end
    executable=file(joinpath(Sys.BINDIR,Base.julia_exename()))
    pointer=Base.JLOptions().image_file
    pointer==C_NULL && error("explicit system image identity unavailable")
    sysimage=file(unsafe_string(pointer))
    Dict("schema"=>"FormulationLab.timing_runtime.v1","julia_version"=>string(VERSION),
        "executable"=>executable,"sysimage"=>sysimage,"project"=>realpath(project),
        "depots"=>copy(DEPOT_PATH),"load_path"=>copy(LOAD_PATH),"packages"=>packages,
        "artifacts"=>artifacts,"uninstalled_host_artifacts"=>sort!(unique(uninstalled)),
        "loaded_caches"=>caches,"loaded_libraries"=>libraries,"system_shared_cache_libraries"=>system,
        "files_sha256"=>files,"path_aliases"=>aliases,"trees"=>trees,
        "environment"=>Dict(k=>get(ENV,k,nothing) for k in ENV_KEYS),
        "platform"=>Dict("kernel"=>string(Sys.KERNEL),"machine"=>Sys.MACHINE,"cpu"=>Sys.CPU_NAME,
            "cpu_threads"=>Sys.CPU_THREADS,"os_build"=>Sys.isapple() ? readchomp(`/usr/bin/sw_vers -buildVersion`) : readchomp(`uname -r`)),
        "julia_threads"=>Threads.nthreads(),"blas_threads"=>BLAS.get_num_threads(),
        "limitations"=>["OS shared-cache libraries identified by OS build and names; not individually byte-hashed.",
            "Uninstalled host artifacts are listed, never downloaded. A later unrecorded library or artifact invalidates the runtime inventory."])
end
end
