module Factorio
using JSON, DataFrames

DATA_DIR = joinpath(@__DIR__, "..", "data")

include("io/load.jl")
include("DataModel/DataModel.jl")

#export Types
export  Electricity,
        Fuel

# Export Assets
export  AssemblingMachine

# Export DataModels
#export AssemblingMachines

# Export Databases
export  DefaultFactorioDataBase

# Export functions
export  consumption,
        tier

end