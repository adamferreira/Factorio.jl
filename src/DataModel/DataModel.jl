using DataFrames
using JSON

abstract type AbstractDataModel end
abstract type Energy end
abstract type Fuel <: Energy end
abstract type Electricity <: Energy end

# DataModel Holding Everything Needed
abstract type FactorioDataBase end

const UniqueID = UInt16
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
    All AbstractDataModel hold and index `ind` to identify them.
    It is used to contruct their unique ids.
    For example let r be the 4th Recipe (assuming UInt8 indextypes).
    model(r) = model(Recipe) = 1 = 00000001
    index(r) = 4 = 00000100
    uid(r) = 00010100
    Thus given an uid, it is possible to deduce its datamodel and its specific values within the datamodel
"""
MODELS = [
    :Item,
    :AssemblingMachine,
    :Fluid,
    :Recipe,
]



"""
    A recipe is an element that have a crafting Time.
    And is meant to be used in a Recipe Graph.
"""
abstract type Recipe <: AbstractDataModel end
#sourcefile(::Type{Recipe}) = "recipe.json"

"""
    An Item is an element that can be inside and inventory, be crafted, or be unlocked.
"""
struct Item <: AbstractDataModel
    name::String
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


# Define UniqueIds methods on all variant of `AbstractDataModel`
for (id, m) in enumerate(MODELS)
    @eval @inline model(x::$m) = UniqueID($id)
    @eval @inline model(::Type{$m}) = UniqueID($id)
end


mutable struct DefaultFactorioDataBase <: FactorioDataBase
    # List of datamodels index by their model id
    datamodels::Vector{DataFrame}
end


"""
    Get the dataframe representing elements of datamodel `T`
"""
function data(d::DefaultFactorioDataBase, ::Type{T})::DataFrame where {T<:AbstractDataModel}
    return d.datamodels[model(T)]
end

"""
    Get the DataFrameRow representing element `x` without explicit mention of its datamodel type
"""
function get(d::DefaultFactorioDataBase, x::UniqueID)::DataFrameRow
    return d.datamodels[model(x)][index(x), :]
end
get(d::DefaultFactorioDataBase, x::Integer)::DataFrameRow = get(d, UniqueID(x))



# Override convertion from 2-tuple to pair
# Used to transform a list of tuples to a list of pairs in load_data
Base.convert(::Type{Pair}, t::Tuple{A,B}) where {A,B} = Pair{A,B}(t[1], t[2])

function load_data(filename, colnames, coltypes, mid::UniqueID)::DataFrame
    # Load the json datafile as a dictionnary
    d = JSON.parsefile(joinpath(DATA_DIR, filename))
    # Prepare empty DataFrame with appropriate column names and types
    # Also ad the "uid" UniqueID column
    df = DataFrame(vcat(:uid => UniqueID[], [(n => t[]) for (n,t) in zip(colnames, coltypes)]))
    # Iterate over dict `d` content
    for (name, desc) in d
        # Append DataFrame row-with_neighbors
        push!(df, vcat(combine(mid, UniqueID(size(df)[1]+1)), [desc[String(c)] for c in colnames]))
    end
    return df
end

load_data(m::Type{<:AbstractDataModel}) = load_data(sourcefile(m), fieldnames(m), fieldtypes(m), model(m))


function DefaultFactorioDataBase()
    return DefaultFactorioDataBase([load_data(Item)])
end

DEFAULT_DB = DefaultFactorioDataBase()
default_db() = DEFAULT_DB

# Every method accepting DefaultFactorioDataBase should also accept the instanciated default
get(x::UniqueID)::DataFrameRow = get(default_db(), x)
get(x::Integer)::DataFrameRow = get(default_db(), x)
function data(t::Type{T})::DataFrame where {T<:AbstractDataModel}
    return data(default_db, t)
end

#items = load_data(Item)
#replace!(x -> "fuel", filter(row -> row.fuel_value > 0, items; view=true).type)
#filter(row -> row.type == "fuel", items)

d = DefaultFactorioDataBase()
@show data(d, Item)