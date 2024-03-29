using DataFrames
using JSON

abstract type AbstractDataModel end
abstract type Energy end
abstract type Fuel <: Energy end
abstract type Electricity <: Energy end

# DataModel Holding Everything Needed
abstract type FactorioDataBase end

DATA_DIR = joinpath(@__DIR__, "..", "..", "data")

"""
    Concatenates the two hashes `a` and `b` into `T`.
    Let's sya T = UInt8 and:
    - a = 10 = 00001010
    - b = 12 = 00001100
    This function returns the new hash 10100000 | 00001100 = 10101100
"""
function combine(a::T, b::T) where {T<:Unsigned}
    return (a << (4*sizeof(T))) | (b & mask(UniqueID))
end

"""
    The mask for an Integer type `T` stored in n bits is
    n/2 `0` bits followed by n/2 `1` bits
    The mask for UInt8 is `00001111`
"""
@inline mask(::Type{T}) where {T<:Unsigned} = T((1 << (4*sizeof(T))) - 1)
"""
    Get the last |`T`|/2 bits of the uid x
"""
@inline index(x::T) where {T<:Unsigned} = x & mask(T)
"""
    Get the first |`T`|/2 bits of the uid x
"""
@inline model(x::T) where {T<:Unsigned} = (~mask(T) & x) >> T(4*sizeof(T))


"""
    A recipe is an element that have a crafting Time.
    And is meant to be used in a Recipe Graph.
    The `tier` of an element is defined as:
    - max(tier(i)+1) for i ∈ I, I being the set of ingredients of the Recipe
"""
struct Recipe <: AbstractDataModel 
    name::String
    tier::Int64
    category::String
    # In seconds
    crafttime::Float64
    ingredients_names::Vector{String}
    ingredients_amounts::Vector{Int64}
    products_names::Vector{String}
    products_amounts::Vector{Int64}
    products_probabilities::Vector{Float64}
end
@inline sourcefile(::Type{Recipe}) = "recipe.json"

"""
    An Item is an element that can be inside and inventory, be crafted, or be unlocked.
    The `tier` of an element is defined as:
    - 0 For raw materials (that can me mined for drilled, and cannot be crafter)
    - max(tier(r)) for r ∈ R, R being the set of recipes that can produce the Item 
"""
struct Item <: AbstractDataModel
    name::String
    tier::Int64
    type::String
    fuel_value::Float64
    stack_size::Int64
end
@inline sourcefile(::Type{Item}) = "item.json"
"""
    An AssemblingMachine is an element that can craft Items/Resources from Items/Resources
"""
struct AssemblingMachine <: AbstractDataModel
    name::String
    # Crafting bonus applied to the recipe's crafting speed
    # The crafting time of a recipe tacking 5 second with a machine at 0.5 crafting speed is thus 5/0.5 = 10s
    crafting_speed::Float64
    # In Watt
    energy_usage::Float64
    # Unit per minute
    pollution::Float64
    module_inventory_size::Int64
    # Crafting Categories (Which kind of recipe this machine supports)
    crafting_categories::Vector{String}
end
@inline sourcefile(::Type{AssemblingMachine}) = "assembling-machine.json"


"""
    A fluid is a base resource that can be transported with pipes
"""
struct Fluid <: AbstractDataModel
    name::String
    default_temperature::Int64
    max_temperature::Int64
    fuel_value::Float64
    emissions_multiplier::Float64
end
@inline sourcefile(::Type{Fluid}) = "fluid.json"

"""
    A Module can be inserted inside a AssemblingMachine to apply some bonuses to it
"""
struct Module <: AbstractDataModel
    # Stored as multipliers
    name::String
    consumption::Float64
    speed::Float64
    productivity::Float64
    pollution::Float64
end
@inline sourcefile(::Type{Module}) = "item.json"


"""
    All AbstractDataModel hold and index `ind` to identify them.
    It is used to contruct their unique ids.
    For example let r be the 4th Recipe (assuming UInt8 indextypes).
    model(r) = model(Recipe) = 1 = 00000001
    index(r) = 4 = 00000100
    uid(r) = 00010100
    Thus given an uid, it is possible to deduce its datamodel and its specific values within the datamodel
"""

datamodels() = Set([:Item, :Recipe, :Fluid, :AssemblingMachine, :Module])

for (id, m) in enumerate(datamodels())
    #@eval @inline model(x::$m) = UniqueID($id)
    @eval @inline model(::Type{$m}) = UniqueID($id)
end


mutable struct DefaultFactorioDataBase <: FactorioDataBase
    # List of datamodels index by their model id
    datamodels::Vector{DataFrame}
    # Recipe graph
    recgraph::MetaGraphsNext.MetaGraph
    # Matrix that stores distance between each pair of recipes
    distmtx::Matrix{Float64}

end

"""
    Default lambdas for loading columns from the the json files
"""
parsecol_fct(m::Type{<:AbstractDataModel})::Dict{Any,Any} = Dict([cname => desc -> desc[String(cname)] for cname in fieldnames(m)])

"""
    Get the dataframe representing elements of datamodel `T`
"""
function data(::Type{T}, db=default_database())::DataFrame where {T<:AbstractDataModel}
    return @inbounds db.datamodels[model(T)]
end

"""
    Get the DataFrameRow representing element `x` without explicit mention of its datamodel type
"""
function get(x::UniqueID, db=default_database())::DataFrameRow
    return db.datamodels[model(x)][index(x),:]
end
get(x::Integer, db=default_database())::DataFrameRow = get(UniqueID(x), db)
function get(x::UniqueID, ::Type{T}, db=default_database())::DataFrameRow where {T<:AbstractDataModel}
    return get(x, db)
end
"""
    Get the DataFrameRow representing element `x` given its name and datamodel type
"""
function get(x::AbstractString, ::Type{T}, db=default_database())::DataFrameRow where {T<:AbstractDataModel}
    # We assure only one element with name `x` exists for datamodel type `T`
    return filter(row -> row.name == x, data(T, db); view=true)[1,:]
end


function _code_ingredients(x, db=default_database())
    vcode = MetaGraphsNext.code_for(db.recgraph, get(x, Recipe, db).uid)
    #return MetaGraphsNext.inneighbors(db.recgraph, vcode) #.|> MetaGraphsNext.label_for(db.recgraph)
    return MetaGraphsNext.inneighbors(db.recgraph, vcode)
end


function ingredients(recipe::Union{UniqueID,String}, db=default_database())::DataFrame
    r = get(recipe, Recipe, db)
    vcode = MetaGraphsNext.code_for(db.recgraph, r.uid)
    ingcodes = MetaGraphsNext.inneighbors(db.recgraph, vcode)
    # Remove model code from uid to get index in Item Dataframe
    inglabels = map(y -> index(MetaGraphsNext.label_for(db.recgraph, y)), ingcodes)
    df = copy(data(Item, db)[inglabels, [:uid,:name]])
    rename!(df, :name => :ingredient)
    # Add the 'amount" column to the dataframe
    df[!,:amount] = map(x -> db.recgraph[MetaGraphsNext.label_for(db.recgraph, x), MetaGraphsNext.label_for(db.recgraph, vcode)].amount, ingcodes)
    # Also add recipe information
    df[!,:crafttime] = map(x -> r.crafttime, ingcodes)
    df[!,:recipe_name] = map(x -> r.name, ingcodes)
    return df
end

"""
    function recipe_distance(db=default_database())::Matrix{Float64}
Returns a Matrix M[i,j] = d, with d the distance between two recipe i and j.
M[i,j] = 0 if i = j or if i and j share the exact same ingredients.
Otherwise, it is an indicator of how close the two recipes are in terme of ingredients.
How its computed, let Δ be:

lab ->                  │ iron-gear-wheel  transport-belt  electronic-circuit 
assembling-machine-1    │ Float64          Float64         Float64
────────────────────────┼─────────────────────────────────────────────────────
iron-plate              │   δ(plate,gear)   δ(plate,belt)   δ(plate,circuit) 
iron-gear-wheel         │       0.0         δ(gear,plate)   δ(gear,circuit) 
electronic-circuit      │   δ(circuit,gear) δ(circuit,belt)     0.0

Where δ(item1,item2) is the shortest path from item1 to item2 in the recipe graph.

We want to avoid this situation:
electric-furnace ->     │ stone-brick  steel-plate  advanced-circuit 
steel-chest             │ Float64          Float64         Float64
────────────────────────┼─────────────────────────────────────────────────────
steel-plate             │   δ(plate,brick)   0.0    δ(plate,circuit)

Where Δ[max(min(δ(plate,brick), 0.0, δ(plate,circuit)))] would lead to Δ(electric-furnace, steel-chest) = 0
So we impose a distance penalty penalty on the number of different ingredients for recipes.
Here, P = 3 - 1 = 2

"""
function recipe_distance(db=default_database())::Matrix{Float64}
    # First compute (minimal) distance between all nodes (items and recipes) of the recipe graph
    # We assume weight 1.0 on all edges as no other weight is relevant here
    N = Graphs.nv(db.recgraph)
    # TODO: Optimize with sparse matrix ?
    distmx = ones(N, N) * Inf
    # As the recipe grpah is directed, matrix `dist` will note be symetric
    # Because dist(i,j) = d, dist(j,i) = Inf
    # We thus use the undirected version of the inner graph of recipe graph
    G = Graphs.SimpleGraph(db.recgraph.graph)
    map(v -> distmx[v,:] = Graphs.dijkstra_shortest_paths(db.recgraph, v).dists, 1:N)
    map(v -> distmx[:,v] = distmx[v,:], 1:N)
    #distmx = [min(distmx[i,j], distmx[j,i]) for i=axes(distmx,1), j=axes(distmx,2)]

    @assert distmx == transpose(distmx)
    
    function compute_distance(r1, r2)::Float64
        # Get ingredients of r1 and r2
        r1_ing = MetaGraphsNext.inneighbors(db.recgraph, r1)
        r2_ing = MetaGraphsNext.inneighbors(db.recgraph, r2)
        # Recipe that do not have ingredient have an infinite distance to other recipes
        if length(r1_ing) == 0 || length(r2_ing) == 0
            return Inf
        end
        # Compute distance penalty on the number of ingredients difference
        penalty = abs(length(r1_ing) - length(r2_ing))
        # Construct a matrix that will store the distance between each combination of ingredients of r1 and r2
        # M[i,j] will be the distance between ingredient i of r1 and ingredient j of r2
        # Get the min between M and transpose(M) to have a symetric matrix at the end
        M = [distmx[r1_ing[i], r2_ing[j]] for i=eachindex(r1_ing), j=eachindex(r2_ing)]
        return min(
            reduce(+, map(i -> reduce(min, M[i,:]), eachindex(r1_ing))),
            reduce(+, map(i -> reduce(min, transpose(M)[i,:]), eachindex(r2_ing)))
        ) + penalty
    end

    # Matrix representing the distance between two recipe
    # Here recipe are indexed by index(r.uid)
    valid_recipes = filter(r -> model(MetaGraphsNext.label_for(db.recgraph, r)) == model(Recipe), Graphs.vertices(db.recgraph))
    recipe_dist = [
        compute_distance(i,j)
        for i ∈ valid_recipes, j ∈ valid_recipes
    ]
    return recipe_dist
end

function similarity_graph(db=default_database(); dist::Float64=0.0)
    # Transform recipe_dist into a boolean Matrix according to `dist` tolerance
    # Also add - (i==j) to remove the identity matrix (M[i,i] = 0)
    M = [(db.distmtx[i,j] == dist) - (i==j) for i=axes(db.distmtx,1), j=axes(db.distmtx,2)]
    # Construct an undirected graph from this boolean matrix
    return Graphs.SimpleGraph(M)
end