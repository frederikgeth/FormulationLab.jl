using Test, FormulationLab, JuMP, JSON3
include("../examples/ivr_constraint_inventory.jl")
const CINV=IVRConstraintInventory

function _inventory_check(b)
    c=CINV.catalog(b);r=CINV.report(b)
    @test c.complete_emitted_coverage
    @test !c.complete_input_coverage
    @test c.covered_constraint_count==num_constraints(b.model;count_variable_in_set_constraints=true)
    @test Set(keys(c.owners))==Set(all_constraints(b.model;include_variable_in_set_constraints=true))
    @test isempty(c.uncovered_constraints)
    @test JSON3.read(JSON3.write(r)).complete_emitted_coverage
    @test length(r.declarations)==length(c.declarations)
    for q in c.declarations
        @test all(ref->is_valid(b.model,ref),q.constraints)
        @test all(ref->q.label in c.owners[ref],q.constraints)
    end
    c
end

@testset "Combined emitted inventory across exact coordinate and lifting options" begin
    for m in (2,3,4),law in ("constant_current","zip","exponential"),
            lifting in (:off,:powers,:bounded_observations),reduced in (false,true),sb in (1e3,1e5)
        net,_=_loadlaw_witness(m,law)
        b=build_opf(net,IVRNLP(;s_base=sb,lifting,load_power_lifting=true,load_power_base=500.,
            load_power_row_scaling=:both,load_power_row_base=100.,row_scaling=:composed,
            specialization=reduced ? :conductor_difference : :off,
            linear_elimination=reduced ? :passive_blocks : :off))
        c=_inventory_check(b)
        @test count(q->q.category==:circuit,c.declarations)==length(b.electrical.equations)+length(b.electrical.kcl)
        @test count(q->q.category==:lifting_definition,c.declarations)==length(b.model.ext[:ivr_lifting].records)
    end
    for m in (2,3,4),filtered in (false,true),lifting in (:off,:bounded_observations)
        net,_,_=_ibr_voltage_witness(m;filtered)
        _inventory_check(build_opf(net,IVRNLP(;lifting)))
    end
end

@testset "Inventory rejects missing, stale and duplicated provenance" begin
    fresh()=build_opf(ivr_compiler_case(conductors=4),IVRNLP(lifting=:bounded_observations))
    b=fresh();_inventory_check(b)
    extra=@constraint(b.model,b.coordinates.real_variables[1]<=123.)
    c=CINV.catalog(b)
    @test !c.complete_emitted_coverage && c.uncovered_constraints==[extra]
    delete(b.model,extra);_inventory_check(b)
    for key in (:ivr_circuit_rows,:ivr_source_fixes,:ivr_lifting)
        b=fresh();delete!(b.model.ext,key)
        @test_throws ArgumentError CINV.catalog(b)
    end
    b=fresh();pop!(b.model.ext[:ivr_circuit_rows])
    @test_throws ArgumentError CINV.catalog(b)
    b=fresh();pop!(b.model.ext[:ivr_source_fixes])
    @test_throws ArgumentError CINV.catalog(b)
    b=fresh();rows=b.model.ext[:ivr_circuit_rows];key=first(k for (k,q) in rows if q.status==:retained);q=rows[key]
    rows[key]=merge(q,(constraints=(first(q.constraints),first(q.constraints)),))
    @test_throws ArgumentError CINV.catalog(b)
    rows[key]=q;delete(b.model,first(q.constraints))
    @test_throws ArgumentError CINV.catalog(b)
    b=fresh();rows=b.model.ext[:ivr_circuit_rows];key=first(k for (k,q) in rows if q.status==:retained);q=rows[key]
    rows[key]=merge(q,(divisor=2q.divisor,))
    @test_throws ArgumentError CINV.catalog(b)
    rows[key]=q;set_normalized_rhs(first(q.constraints),1.)
    @test_throws ArgumentError CINV.catalog(b)
    b=fresh();q=first(values(b.model.ext[:ivr_source_fixes]))
    fix(b.coordinates.real_variables[q.native_coordinate],999.;force=true)
    @test_throws ArgumentError CINV.catalog(b)
    b=fresh();pop!(b.model.ext[:ivr_lifting].records)
    @test !CINV.catalog(b).complete_emitted_coverage
    b=fresh();q=first(b.model.ext[:ivr_lifting].records);delete(b.model,q.definition_real)
    @test_throws ArgumentError CINV.catalog(b)
end
