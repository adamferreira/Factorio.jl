using JuMP # Modeling interface
using Ipopt # NLP solver
using Juniper # Branch and Bound
using LinearAlgebra # Dot vector product

"""
 Both Oil refinery and Chemical plant have 3 slots for modules
"""

@enum Recipes begin
    Basic_oil_processing = 1
    Advanced_oil_processing
    Heavy_oil_cracking 
    Light_oil_cracking
    Coal_liquefaction
end

@enum Modules begin
    Speed_Module_1 = 1
    Speed_Module_2
    Speed_Module_3
    Productivity_Module_1
    Productivity_Module_2
    Productivity_Module_3
    Efficiency_Module_1
    Efficiency_Module_2
    Efficiency_Module_3
end

@enum Ingredients begin
    Crude_Oil = 1
    Coal
    Water
    Petroleum_Gas
    Light_Oil
    Heavy_Oil
end

""" 
    Constants
"""
# Oil Recipes (https://wiki.factorio.com/Oil_processing)

# Base craft times of Recipes (in seconds)
_BCT = Dict(
    Basic_oil_processing    => 5.0,
    Advanced_oil_processing => 5.0,
    Heavy_oil_cracking      => 2.0,
    Light_oil_cracking      => 2.0,
    Coal_liquefaction       => 5.0
)

# Base consumptions of Ingredients for each Recipes (in per unit)
_BC = Dict(
    Basic_oil_processing    => Dict(Crude_Oil => 100.0, Coal => 0.0, Water => 0.0, Petroleum_Gas => 0.0, Light_Oil => 0.0, Heavy_Oil => 0.0),
    Advanced_oil_processing => Dict(Crude_Oil => 100.0, Coal => 0.0, Water => 50.0, Petroleum_Gas => 0.0, Light_Oil => 0.0, Heavy_Oil => 0.0),
    Heavy_oil_cracking      => Dict(Crude_Oil => 0.0, Coal => 0.0, Water => 30.0, Petroleum_Gas => 0.0, Light_Oil => 0.0, Heavy_Oil => 40.0),
    Light_oil_cracking      => Dict(Crude_Oil => 0.0, Coal => 0.0, Water => 30.0, Petroleum_Gas => 0.0, Light_Oil => 30.0, Heavy_Oil => 0.0),
    Coal_liquefaction       => Dict(Crude_Oil => 0.0, Coal => 10.0, Water => 50.0, Petroleum_Gas => 0.0, Light_Oil => 0.0, Heavy_Oil => 25.0)
)

# Base Production of Ingredients for each Recipes (in per unit)
_BP = Dict(
    Basic_oil_processing    => Dict(Crude_Oil => 0.0, Coal => 0.0, Water => 0.0, Petroleum_Gas => 45.0, Light_Oil => 0.0, Heavy_Oil => 0.0),
    Advanced_oil_processing => Dict(Crude_Oil => 0.0, Coal => 0.0, Water => 0.0, Petroleum_Gas => 55.0, Light_Oil => 45.0, Heavy_Oil => 25.0),
    Heavy_oil_cracking      => Dict(Crude_Oil => 0.0, Coal => 0.0, Water => 0.0, Petroleum_Gas => 0.0, Light_Oil => 30.0, Heavy_Oil => 0.0),
    Light_oil_cracking      => Dict(Crude_Oil => 0.0, Coal => 0.0, Water => 0.0, Petroleum_Gas => 20.0, Light_Oil => 0.0, Heavy_Oil => 0.0),
    Coal_liquefaction       => Dict(Crude_Oil => 0.0, Coal => 0.0, Water => 0.0, Petroleum_Gas => 10.0, Light_Oil => 20.0, Heavy_Oil => 90.0)
)

# Bonus of modules (https://wiki.factorio.com/Module)

# Speed Bonus
_SB = Dict(
    Speed_Module_1 => +.2,
    Speed_Module_2 => +.3,
    Speed_Module_3 => +.5,
    Productivity_Module_1 => -.05,
    Productivity_Module_2 => -.07,
    Productivity_Module_3 => -.1,
    Efficiency_Module_1 => +.0,
    Efficiency_Module_2 => +.0,
    Efficiency_Module_3 => +.0
)

# Energy consumptions bonus
_CB = Dict(
    Speed_Module_1 => +.5,
    Speed_Module_2 => +.6,
    Speed_Module_3 => +.7,
    Productivity_Module_1 => +.4,
    Productivity_Module_2 => +.6,
    Productivity_Module_3 => +.8,
    Efficiency_Module_1 => -.3,
    Efficiency_Module_2 => -.4,
    Efficiency_Module_3 => -.5
)

# Productivity bonus
_PB = Dict(
    Speed_Module_1 => +.0,
    Speed_Module_2 => +.0,
    Speed_Module_3 => +.0,
    Productivity_Module_1 => +.04,
    Productivity_Module_2 => +.06,
    Productivity_Module_3 => +.1,
    Efficiency_Module_1 => +.0,
    Efficiency_Module_2 => +.0,
    Efficiency_Module_3 => +.0
)

# Skip Polution bonus


"""
    Transform from Dict model (user friendly) to Matrix model
"""

function dict_to_array(d)
    a = zeros(Float64, length(d))
    for (k,v) in d
        a[Int64(k)] = v
    end
    return a
end

function dict_to_matrix(d)
    m = zeros(Float64, length(d), length(first(d)[2]))
    for (k,v) in d
        for (k2,v2) in v
            m[Int64(k), Int64(k2)] = v2
        end
    end
    return m
end

BCT = dict_to_array(_BCT)
BC = dict_to_matrix(_BC)
BP = dict_to_matrix(_BP)
SB = dict_to_array(_SB)
CB = dict_to_array(_CB)
PB = dict_to_array(_PB)



#model = Model(Ipopt.Optimizer)
#model = Model(SCIP.Optimizer)
#model = Model(GLPK.Optimizer)

nl_solver = optimizer_with_attributes(Ipopt.Optimizer, "print_level"=>3)
minlp_solver = optimizer_with_attributes(Juniper.Optimizer, "nl_solver"=>nl_solver)
model = Model(minlp_solver)
# No need for MIP solver for feasibilty pump as finding a solution to this model is easy

# TODO: Model without moduls -> linear
"""
    Sets
"""
# Recipes
R = 1:length(instances(Recipes))
# Modules
M = 1:length(instances(Modules))
# Resources 
I = 1:length(instances(Ingredients))
# Assembling Machines
A = 1:3

""" 
    Variables
"""
# Integer variables, Number of modules `m` used by machine `a`
@variable(model, v_um[a in A, m in M], integer = true)
# Binary variables, Equals 1 if machine `a` follows recipe `r`, Equals 0 otherwise
@variable(model, v_ur[a in A, r in R], binary = true)
# Real variables representing the productivity of a machine `a`
@variable(model, v_productivity[a in A])
# Real variables representing the speed of a machine `a`
@variable(model, v_speed[a in A])
# Real variables representing the production of ingredient `i` by machine `a`
@variable(model, v_production[a in A, i in I])
# Real variables representing the consumption of ingredient `i` by machine `a`
@variable(model, v_consumption[a in A, i in I])

""" 
    Constraints
"""
# A given machine (Oil refinery and Chemical) can only uses at most 3 modules
@constraint(model, c_maxmod[a in A], sum(v_um[a,:]) <= 3)
# A given machine can only follow a single recipe at most
@constraint(model, c_maxrec[a in A], sum(v_ur[a,:]) <= 1)
# Constraints computing the crafting speed of a machine given its modules
@constraint(model, c_speed[a in A], v_speed[a] == v_um[a,:] ⋅ SB)

# The crafting speed of a machine `a` in second
speed = (a) -> 1. + (v_um[a,:] ⋅ SB)
# Productivity of machine `a` in item
productivity = (a) -> 1. + (v_um[a,:] ⋅ PB)
# Production factor of a machines
prod_factor = (a) -> ((1. .+ SB) .* (1. .+ PB)) ⋅ v_um[a,:] 

production = (a,i) -> (1. + SB) 

# Production constraints, at which rate (item/sec) a machine `a` with recipe `r` produces ingredient `i`
# The production rate is the base production rate adjusted with the machine's speed and productivity
#@NLconstraint(model, c_production[a in A, i in I], v_production[a,i] == (BP[:,i] .* (BCT .* (v_um[a,:] ⋅ SB))) ⋅ v_ur[a,:])

#@objective(model, Min, sum(v_ur))

#optimize!(model)