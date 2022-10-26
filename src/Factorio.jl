module Factorio
using JSON, DataFrames

DATA_DIR = joinpath(@__DIR__, "..", "data")

include("io/load.jl")

include("DataModel/DataModel.jl")

m = DefaultFactorioDataBase()
a = AssemblingMachine(3, m)
@show typeof(a)
@show sizeof(a)
@show consumption(Electricity, a)
@show consumption(Fuel, a)
@show tier(a)
@show typeof(a)

end