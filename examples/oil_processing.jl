using JuMP # Modeling interface
using GLPK # MIP solver
#using Ipopt # NLP solver
#using Juniper # Branch and Bound
using LinearAlgebra # Dot vector product
using HiGHS

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


function nl_model()
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

    @variable(model, v_rate[a in A, r in R, i in I])

    """ 
        Constraints
    """
    # The crafting speed of a machine `a` in second
    speed = (a) -> 1. + (v_um[a,:] ⋅ SB)
    # Productivity of machine `a` in item
    productivity = (a) -> 1. + (v_um[a,:] ⋅ PB)

    # A given machine (Oil refinery and Chemical) can only uses at most 3 modules
    @constraint(model, c_maxmod[a in A], sum(v_um[a,:]) <= 3)
    # A given machine can only follow a single recipe at most
    @constraint(model, c_maxrec[a in A], sum(v_ur[a,:]) <= 1)
    # Constraints computing the crafting speed factor (in per unit) of a machine `a` given its modules
    @constraint(model, c_speed[a in A], v_speed[a] == 1. + (v_um[a,:] ⋅ SB))
    @constraint(model, c_productivity[a in A], v_productivity[a] == 1. + (v_um[a,:] ⋅ PB))

    # The production rate (item/sec) at witch a machine `a` with recipe `r` produces ingredient `i`
    # v_rate[a,r,i] == (BP[r,i] / BCT[r]) * (v_speed[a] / v_productivity[a]) * v_ur[a,r]
    @NLconstraint(model, c_rate[a in A, r in R, i in I], v_rate[a,r,i] * v_productivity[a] * BCT[r] == (BP[r,i] * v_speed[a] * v_productivity[a]) * v_ur[a,r])
    @constraint(model, c_production[a in A, i in I], v_production[a,i] == sum(v_rate[a,:,i]))

    @objective(model, Max, sum(v_production[:,Int64(Heavy_Oil)]))

    optimize!(model)

end

# Linear model
model = Model(GLPK.Optimizer)
"""
Sets
"""
# Recipes
R = 1:length(instances(Recipes))
# Resources 
I = 1:length(instances(Ingredients))
# Assembling Machines
A = 1:8
# End products
P = [Int64(Petroleum_Gas), Int64(Heavy_Oil), Int64(Light_Oil)]

""" 
Variables
"""
# Binary variables, Equals 1 if machine `a` follows recipe `r`, Equals 0 otherwise
@variable(model, v_ur[a in A, r in R], binary = true)
# Real variables representing the production of ingredient `i` by machine `a`
@variable(model, v_production[a in A, i in I])
# Real variables representing the consumption of ingredient `i` by machine `a`
@variable(model, v_consumption[a in A, i in I])

""" 
Constraints
"""
# A given machine can only follow a single recipe at most
@constraint(model, c_maxrec[a in A], sum(v_ur[a,:]) <= 1)
# The production rate (item/sec) at witch a machine `a` produces ingredient `i`
@constraint(model, c_production[a in A, i in I], v_production[a,i] == (BP[:,i] ./ BCT) ⋅ v_ur[a,:])
@constraint(model, c_consumption[a in A, i in I], v_consumption[a,i] == (BC[:,i] ./ BCT) ⋅ v_ur[a,:])
# The net consumption of end product must be positive ! 
net_production = (i) -> sum(v_production[:,i] .- v_consumption[:,i])
@constraint(model, c_endprod[i in P], net_production(i) >= 0)

@objective(model, Max, net_production(Int64(Petroleum_Gas)) - net_production(Int64(Heavy_Oil)) - net_production(Int64(Light_Oil)) - sum(v_consumption[:, Int64(Crude_Oil)]))
optimize!(model)

@show value.(v_ur)
@show value.(v_production)
@show value.(v_consumption)
@show value.(v_production .- v_consumption)
@show value(net_production(Int64(Petroleum_Gas)) - net_production(Int64(Heavy_Oil)) - net_production(Int64(Light_Oil)))


# TODO : make machine type and moducles combination into a single variable
#|Machine types| x |Modules comination (1 to 4) |

# Matrix to reprensent Module combinations
# Columns are modules types and rows are combinations
# We must satisfy sum(M[c,:]) == 4 (maximum number of modules in a machine)
# TODO: make a column generation model with those many variables ?