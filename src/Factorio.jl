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

function factorio_init()
    # Step 1: Parse raw data from json files
    models = [DataFrame() for m in datamodels()]
    models[model(Item)] = load_items()
    models[model(Recipe)] = load_recipes()
    models[model(Fluid)] = load_data(Fluid, parsecol_fct(Fluid))
    models[model(AssemblingMachine)] = load_data(AssemblingMachine, parsecol_fct(AssemblingMachine))
    # Step 2: Create DB with raw data and empty recipe graph
    db = DefaultFactorioDataBase(models, RecipeGraph(nothing))
    db.recgraph = RecipeGraph(db)
    # Step 3: Use raw data to construct recipe graph
    # Add all potential ingredients/products as nodes in the graph
    uids = Set(vcat(data(Item, db).uid, data(Fluid, db).uid))
    [add_recipe_node!(db.recgraph, RecipeGraphNode(uid)) for uid in uids]

    function try_get(x::AbstractString, db)
        for T in [Item, Fluid]
            try
                return get(x, T, db)
            catch y
                continue
            end
        end
        return nothing
    end

    # Temove Barrel recipes as they introduces cycles in the recipe graph
    # Water produces water-barel that produces water
    # This hides the fact that 'water' is a raw material (no inbound recipe)
    for r in eachrow(filter(row -> !occursin("-barrel", row.name), data(Recipe, db); view=true))
        # Add current recipe as a node in the grah
        add_recipe_node!(db.recgraph, RecipeGraphNode(r.uid))
        # Add an edge between ingredients and the recipe node
        for i in 1:length(r.ingredients_names)
            ing = try_get(r.ingredients_names[i], db)
            add_recipe_edge!(db.recgraph, ing.uid, r.uid, RecipeGraphEdge(r.ingredients_amounts[i], 1.0))
        end
        # Add an edge between the recipe and its products
        for i in 1:length(r.products_names)
            prod = try_get(r.products_names[i], db)
            add_recipe_edge!(db.recgraph, r.uid, prod.uid, RecipeGraphEdge(r.products_amounts[i], r.products_probabilities[i]))
        end
    end

    # Step 4: Use recipe graph to deduce Items and Recipes tiers
    return db
end
# Fill default Database
DEFAULT_DB = factorio_init()

export default_database

# Export DataModels
export  DefaultFactorioDataBase,
        UniqueID,
        Item, Recipe, Fluid, AssemblingMachine
        data, get

# Datamodel miscellaneous (for tests)
export  uid,
        mask,
        model,
        index


# Export Recipe graph logic
export  RecipeGraph,
    ingredients


# plot 
export rplot

end