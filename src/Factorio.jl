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
    models[model(Fluid)] = load_fluids()
    models[model(AssemblingMachine)] = load_machines()
    # Step 2: Create DB with raw data and empty recipe graph
    db = DefaultFactorioDataBase(models, RecipeGraph(nothing), zeros(1,1))
    db.recgraph = RecipeGraph(db)
    # Step 2.5: Also add Fluid in Item as they can be used as resource
    # Their stack_size will be 0 and type will be "fluid"
    for f in eachrow(data(Fluid, db))
        uid = combine(model(Item), UniqueID(size(data(Item, db))[1]+1))
        push!(data(Item, db), [uid, f.name, -1, "fluid", f.fuel_value, 0])
    end
    # Step 3: Use raw data to construct recipe graph
    # Add all potential ingredients/products as nodes in the graph
    uids = Set(data(Item, db).uid)
    [add_recipe_node!(db.recgraph, RecipeGraphNode(uid)) for uid in uids]

    # Not usefull anymore as we put Fluids in Item datamodel
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
    for r in eachrow(data(Recipe, db))#eachrow(filter(row -> !occursin("-barrel", row.name), data(Recipe, db); view=true))
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
    #   Step 4.1: Mark all raw_material (Item or Fluid) as tier 0
    #   Is defined as a raw materiel an element that cannot be crafted, BUT is used in at least one recipe
    raws = filter(x -> Graphs.indegree(db.recgraph, x) == 0 && Graphs.outdegree(db.recgraph, x) >= 1, Graphs.vertices(db.recgraph))
    map(code -> get(MetaGraphsNext.label_for(db.recgraph, code), db).tier = 0, raws)
    # Setp 4.2: Remove edge that creates eventual cycles in the graph
    cycles = Graphs.simplecycles(db.recgraph)
    map(c -> MetaGraphsNext.rem_edge!(db.recgraph, c[1], c[2]), cycles)
    #   Step 4.3: Compute tier 1 recipes, aka recipes that only consumes tiers 0 ingredients
    # Very bad complexity algorithm to compute tiers
    tiers = zeros(Graphs.nv(db.recgraph)) .- 1
    function compute_tier(code)::Int64
        label = MetaGraphsNext.label_for(db.recgraph, code)
        # Tier already computed
        if tiers[code] > -1
            return tiers[code]
        end

        if Graphs.indegree(db.recgraph, code) == 0 && Graphs.outdegree(db.recgraph, code) >= 1
            tiers[code] = 0
            return tiers[code]
        end

        # Only iterate on parent nodes
        if model(label) == model(Recipe)
            tiers[code] = 1 + reduce(max, compute_tier.(MetaGraphsNext.inneighbors(db.recgraph, code)))
            return tiers[code]
        else
            tiers[code] = reduce(max, compute_tier.(MetaGraphsNext.inneighbors(db.recgraph, code)))
            return tiers[code]
        end
    end
    # Call `compute_tier` on all nodes that have parents
    compute_tier.(filter(x -> Graphs.indegree(db.recgraph, x) > 0, Graphs.vertices(db.recgraph)))
    # Apply computed tiers
    map(code -> get(MetaGraphsNext.label_for(db.recgraph, code), db).tier = tiers[code], Graphs.vertices(db.recgraph))


    # TODO: Re-introduced removed edges that created cycles prior to tier computation ?
    # Step 5, compute distance between each paris of recipes so that they can be grouped together by likeliness
    db.distmtx = recipe_distance(db)
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
        recipe_distance, similarity_graph

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