module Factorio
using JSON, DataFrames

using Graphs, MetaGraphsNext, GraphPlot

DATA_DIR = joinpath(@__DIR__, "..", "data")


function Graphs.rem_vertices!(meta_graph::MetaGraph, codes)
    for c in codes
        Graphs.rem_vertex!(meta_graph, c)
    end
end

include("DataModel/recipes.jl")
include("DataModel/DataModel.jl")
include("io/load.jl")

# Global Database
defaultdb = load_default()
database() = defaultdb
recipes() = database().recgraph

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

export  database,
        recipes

# Recipe functions
export  RecipeGraph
        add_recipe_node!,
        add_recipe_edge!,
        labels,
        codes,
        RecipeNode,
        RecipeEdge,
        with_neighbors,
        with_producers,
        with_consumers,
        consumes_any,
        consumes_all,
        consumes_only,
        related_graph

# plot 
export rplot

end