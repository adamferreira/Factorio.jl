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
include("DataModel/DataModel2.jl")
include("io/load.jl")

# Global Database
#FACTORIO_DEFAULT_DB = load_default()
#recipes() = database().recgraph

#export Types
export  Electricity,
        Fuel

# Export DataModels
export  DefaultFactorioDataBase,
        UniqueElement,
        database
for e in vcat(MODELS, DATAMODELS)
    @eval export $e
end
# Datamodel miscellaneous (for tests)
export  uid,
        mask,
        model,
        index

"""
# Export Recipe graph logic
export  RecipeGraph,
        add_recipe_node!,
        add_recipe_edge!,
        labels,
        codes, code,
        RecipeNode,
        RecipeEdge,
        products,
        ingredients,
        with_neighbors,
        with_products,
        with_ingredients,
        consumes_any,
        consumes_all,
        consumes_only,
        related_graph,
        parents,
        children
"""

# plot 
export rplot

end