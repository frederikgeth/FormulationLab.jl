# Optional BMOPFTools replay oracle

BMOPFTools is not a package or default test dependency. To run the retained
nonlinear replay comparisons using the sibling PowerOptLab development environment:

```sh
julia --project=../PowerOptLab.jl -e 'push!(LOAD_PATH, joinpath(pwd(), "test")); include("test/runtests.jl"); include("test/integration/replay.jl")'
```

The ordinary suite defines the fixtures consumed by the replay testsets. The
callback is explicit and the integration environment owns BMOPFTools and Ipopt.
The migrated PowerOptLab also has a small forwarding/replay regression test in
`test/formulationlab_tests.jl`.
