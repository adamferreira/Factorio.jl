module Factorio
using JSON, DataFrames
using Graphs, MetaGraphsNext, GraphPlot

DATA_DIR = joinpath(@__DIR__, "..", "data")


function Graphs.rem_vertices!(meta_graph::MetaGraph, codes)
    for c in codes
        Graphs.rem_vertex!(meta_graph, c)
    end
end

# Global Database
DEFAULT_DB = nothing
function default_database()
    return DEFAULT_DB
end

include("DataModel/recipes.jl")
include("DataModel/DataModel.jl")
include("io/load.jl")
include("io/load2.jl")

# Fill default Database
DEFAULT_DB = factorio2_init()

export default_database

# Export DataModels
export  DefaultFactorioDataBase,
        UniqueID,
        Item, Recipe, Fluid, AssemblingMachine
        data, get
        recipe_distance, similarity_graph

# Datamodel miscellaneous (for tests)
export  uid,
        mask,
        combine,
        model,
        index


# Export Recipe graph logic
export  RecipeGraph,
    ingredients


# plot 
export rplot

end