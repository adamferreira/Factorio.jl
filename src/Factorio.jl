module Factorio
using JSON, DataFrames

using Graphs, MetaGraphsNext, GraphPlot

DATA_DIR = joinpath(@__DIR__, "..", "data")

include("DataModel/recipes.jl")
include("DataModel/DataModel.jl")
include("io/load.jl")

# Global Database
defaultdb = load_default()

database() = defaultdb

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

export database, RecipeGraph, add_recipe_node!, add_recipe_edge!, RecipeNode, RecipeEdge
# plot 
export rplot
end