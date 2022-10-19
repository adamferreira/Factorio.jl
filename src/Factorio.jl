module Factorio
using JSON, DataFrames

DATA_DIR = joinpath(@__DIR__, "..", "data")

include("IO/load.jl")

include("DataModel/DataModel.jl")

load_assembling_machines()
a = AssemblingMachine(5)
@show electricity_usage(AssemblingMachines(), a)
@show tier(a)
@show typeof(a)
end