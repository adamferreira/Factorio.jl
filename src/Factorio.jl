module Factorio
using JSON, DataFrames
using Graphs, MetaGraphsNext, GraphPlot
import Downloads

DATA_DIR = joinpath(@__DIR__, "..", "data")


function Graphs.rem_vertices!(meta_graph::MetaGraph, codes)
    for c in codes
        Graphs.rem_vertex!(meta_graph, c)
    end
end

# Global Database — populated in __init__ so it reads the current JSON on every load.
DEFAULT_DB = nothing
function default_database()
    return DEFAULT_DB
end

include("DataModel/recipes.jl")
include("DataModel/DataModel.jl")
include("io/load.jl")
include("io/load2.jl")

function __init__()
    global DEFAULT_DB = factorio2_init()
end

export default_database

# Export DataModels
export  DefaultFactorioDataBase,
        UniqueID,
        Item, Recipe, Fluid, AssemblingMachine, Module, Technology, Planet,
        data, get,
        recipe_distance, similarity_graph

# Datamodel miscellaneous (for tests)
export  uid,
        mask,
        combine,
        model,
        index


# Export Recipe graph logic
export  RecipeGraph,
    ingredients,
    download_icons


# plot 
export rplot

end