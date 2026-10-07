using Test,JuMP,Ipopt,JSON3
include(joinpath(@__DIR__,"..","examples","ivr_row_scaling_control.jl"))
include(joinpath(@__DIR__,"..","examples","ivr_warm_start_control.jl"))
include(joinpath(@__DIR__,"..","examples","ivr_iterate_capture.jl"))
const R=IVRRowScalingControl;const W=IVRWarmStartControl;const C=IVRIterateCapture
const OUT=get(ENV,"IVR_WARM_CONTROL_OUTPUT",mktempdir())
mkpath(OUT)
@testset "Representable warm-start row units" begin
 runs=[]
 for arm in (:held,:unit)
  m=Model(Ipopt.Optimizer)
  @variable(m,.1<=x<=4,start=2.5)
  @variable(m,y<=5,start=3.)
  @variable(m,z==.5)
  @constraint(m,balance,x+y+z==3.5)
  @constraint(m,circle,x^2+y^2<=8.)
  @constraint(m,lower,200x>=40.)
  @constraint(m,upper,400y<=2000.)
  @constraint(m,nonlinear,exp(.1x)+y>=1.)
  @objective(m,Min,1000*(x-1)^2+2000*(y-2)^2+7*x*y+z^2)
  trace=C.attach!(m)
  rows=ones(5);rows[C.EXT.row(unsafe_backend(m),optimizer_index(lower))]=.5
  rows[C.EXT.row(unsafe_backend(m),optimizer_index(upper))]=.25
  scale=100/4017.5
  @test_throws ArgumentError W.seed!(m;objective_scale=0.,row_scales=rows)
  @test_throws ArgumentError W.seed!(m;objective_scale=scale,row_scales=fill(NaN,5))
  @test_throws ErrorException W.seed!(m;objective_scale=scale,row_scales=[rows;1.])
  @test dual_start_value(lower)===nothing # failed preflight must not mutate
  seed=W.seed!(m;objective_scale=scale,row_scales=rows)
  @test seed.rows==5
  @test dual_start_value(lower)==.5/scale
  @test dual_start_value(upper)==-.25/scale
  options=merge((;print_level=8,tol=1e-10,bound_relax_factor=0.,max_iter=100,acceptable_iter=0),R.settings(unit_rows=arm==:unit),W.settings())
  for (k,v) in pairs(options);set_optimizer_attribute(m,String(k),v);end
  open(joinpath(OUT,"$(arm).log"),"w") do io
   redirect_stdout(io) do;optimize!(m);Base.Libc.flush_cstdio();end
  end
  open(joinpath(OUT,"$(arm)_raw.json"),"w") do io;JSON3.write(io,trace);end
  cap=C.finish(m,trace)
  @test is_solved_and_feasible(m)
  declared=arm==:unit ? ones(5) : rows
  for rec in trace.records;@test R.verify(rec,scale,declared).passed;end
  open(joinpath(OUT,"$(arm).json"),"w") do io;JSON3.write(io,cap);end
  push!(runs,(;objective=objective_value(m),point=value.([x,y,z])))
 end
 @test runs[1].objective≈runs[2].objective atol=1e-8 rtol=1e-8
 @test runs[1].point≈runs[2].point atol=1e-7
 # A genuinely two-sided row cannot be seeded by this one-sided recipe.
 m=Model(Ipopt.Optimizer);@variable(m,x,start=1.);@objective(m,Min,x^2)
 @constraint(m,interval,.5<=2x<=3.);C.attach!(m)
 @test_throws ArgumentError W.seed!(m;objective_scale=1.,row_scales=[1.])
 @test dual_start_value(interval)===nothing
end
println("Native logs retained at ",OUT)
