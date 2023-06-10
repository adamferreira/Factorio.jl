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
    crafting_speed::Float64
    energy_usage::Float64
    pollution::Float64
    module_inventory_size::Int64
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
    All AbstractDataModel hold and index `ind` to identify them.
    It is used to contruct their unique ids.
    For example let r be the 4th Recipe (assuming UInt8 indextypes).
    model(r) = model(Recipe) = 1 = 00000001
    index(r) = 4 = 00000100
    uid(r) = 00010100
    Thus given an uid, it is possible to deduce its datamodel and its specific values within the datamodel
"""

datamodels() = Set([:Item, :Recipe, :Fluid, :AssemblingMachine])

for (id, m) in enumerate(datamodels())
    #@eval @inline model(x::$m) = UniqueID($id)
    @eval @inline model(::Type{$m}) = UniqueID($id)
end


mutable struct DefaultFactorioDataBase <: FactorioDataBase
    # List of datamodels index by their model id
    datamodels::Vector{DataFrame}
    # Recipe graph
    recgraph::MetaGraphsNext.MetaGraph
end

"""
    Default lambdas for loading columns from the the json files
"""
parsecol_fct(m::Type{<:AbstractDataModel})::Dict{Any,Any} = Dict([cname => desc -> desc[String(cname)] for cname in fieldnames(m)])


function load_data(filename, colnames, coltypes, mid::UniqueID, parsecol)::DataFrame
    # Load the json datafile as a dictionnary
    d = JSON.parsefile(joinpath(DATA_DIR, filename))
    # Prepare empty DataFrame with appropriate column names and types
    # Also ad the "uid" UniqueID column
    df = DataFrame(vcat(:uid => UniqueID[], [(n => t[]) for (n,t) in zip(colnames, coltypes)]))
    # Iterate over dict `d` content
    for (name, desc) in d
        # Compute element's Unique Id
        uid = combine(mid, UniqueID(size(df)[1]+1))
        # Get "trival" 
        # Append DataFrame row-with_neighbors
        push!(df, vcat(uid, [parsecol[c](desc) for c in colnames]))#[desc[String(c)] for c in colnames]))
    end
    return df
end
load_data(m::Type{<:AbstractDataModel}, parsecol) = load_data(
    sourcefile(m),
    fieldnames(m),
    fieldtypes(m),
    model(m),
    parsecol
)

function load_items()::DataFrame
    # Default column parsing lambdas
    parsecol = parsecol_fct(Item)
    # Add default tier column to datamodel
    parsecol[:tier] = desc -> -1
    df = load_data(Item, parsecol)
    # Add a new item type `fuel`
    # I.e. items with non-zero fuel value
    replace!(x -> "fuel", filter(row -> row.fuel_value > 0, df; view=true).type)
    return df
end

function load_recipes()::DataFrame
    # Default column parsing lambdas
    parsecol = parsecol_fct(Recipe)
    # Add default tier column to datamodel
    parsecol[:tier] = desc -> -1
    # "craftime" is called "energy" in the json datafile
    parsecol[:crafttime] = desc -> desc["energy"]
    # Recipe's ingredients ids and amounts
    parsecol[:ingredients_names] = desc -> [desc["ingredients"][i]["name"] for i in 1:length(desc["ingredients"])]
    parsecol[:ingredients_amounts] = desc -> [desc["ingredients"][i]["amount"] for i in 1:length(desc["ingredients"])]
    # Recipes's products ids, amounts, and products_probabilities
    parsecol[:products_names] = desc -> [desc["products"][i]["name"] for i in 1:length(desc["products"])]
    parsecol[:products_amounts] = desc -> [desc["products"][i]["amount"] for i in 1:length(desc["products"])]
    parsecol[:products_probabilities] = desc -> [desc["products"][i]["probability"] for i in 1:length(desc["products"])]
    return load_data(Recipe, parsecol)
end

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
    for r in eachrow(data(Recipe))
        @show r
    end

    # Step 4: Use recipe graph to deduce Items and Recipes tiers
    return db
end
DEFAULT_DB = factorio_init()


"""
    Get the dataframe representing elements of datamodel `T`
"""
function data(::Type{T})::DataFrame where {T<:AbstractDataModel}
    return DEFAULT_DB.datamodels[model(T)]
end

"""
    Get the DataFrameRow representing element `x` without explicit mention of its datamodel type
"""
function get(x::UniqueID)::DataFrameRow
    return DEFAULT_DB.datamodels[model(x)][index(x),:]
end
get(x::Integer)::DataFrameRow = get(UniqueID(x))
"""
    Get the DataFrameRow representing element `x` given its name and datamodel type
"""
function get(x::AbstractString, ::Type{T})::DataFrameRow where {T<:AbstractDataModel}
    # We assure only one element with name `x` exists for datamodel type `T`
    return filter(row -> row.name == x, data(T); view=true)[1,:]
end