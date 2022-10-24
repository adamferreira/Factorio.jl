module Factorio
using JSON, DataFrames

DATA_DIR = joinpath(@__DIR__, "..", "data")

include("IO/load.jl")

include("DataModel/DataModel.jl")

m = DefaultFactorioDataBase()
a = AssemblingMachine(3, m)
@show sizeof(a)
#@show consumption(Electricity, AssemblingMachines(), a)
#@show consumption(Fuel, AssemblingMachines(), a)
#@show tier(a)
#@show typeof(a)
end