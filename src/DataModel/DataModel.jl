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
    #:Fluid,
    :Recipe,
]



"""
    A recipe is an element that have a crafting Time.
    And is meant to be used in a Recipe Graph.
"""
abstract type Recipe <: AbstractDataModel end
#sourcefile(::Type{Recipe}) = "recipe.json"
#attributes(::Type{Recipe}) = ["name", "default_temperature", "max_temperature", "fuel_value", "emissions_multiplier"]
#attributes_types(::Type{Recipe}) = [String, String, Int64, Int64]

"""
    An Item is an element that can be inside and inventory, be crafted, or be unlocked.
"""
abstract type Item <: AbstractDataModel end
@inline sourcefile(::Type{Item}) = "item.json"
@inline attributes(::Type{Item}) = ["name", "type", "fuel_value", "stack_size"]
@inline attributes_types(::Type{Item}) = [String, String, Float64, Int64]

"""
    An AssemblingMachine is an element that can craft Items/Resources from Items/Resources
"""
abstract type AssemblingMachine <: AbstractDataModel end
@inline sourcefile(::Type{AssemblingMachine}) = "assembling-machine.json"
@inline attributes(::Type{AssemblingMachine}) = ["name", "crafting_speed", "energy_usage", "pollution"]
@inline attributes_types(::Type{AssemblingMachine}) = [String, Float64, Float64, Float64]


# Define UniqueIds methods on all variant of `AbstractDataModel`
for (id, m) in enumerate(MODELS)
    @eval @inline model(x::$m) = UniqueID($id)
    @eval @inline model(::Type{$m}) = UniqueID($id)
end

# Override convertion from 2-tuple to pair
# Used to transform a list of tuples to a list of pairs in load_data
Base.convert(::Type{Pair}, t::Tuple{A,B}) where {A,B} = Pair{A,B}(t[1], t[2])

function load_data(filename::AbstractString, colnames::Vector{<:AbstractString}, coltypes::Vector{DataType}, mid::UniqueID)::DataFrame
    # Load the json datafile as a dictionnary
    d = JSON.parsefile(joinpath(DATA_DIR, filename))
    # Prepare empty DataFrame with appropriate column names and types
    # Also ad the "uid" UniqueID column
    df = DataFrame(vcat("uid" => UniqueID[], [(n => t[]) for (n,t) in zip(colnames, coltypes)]))
    # Iterate over dict `d` content
    for (name, desc) in d
        # Append DataFrame row-with_neighbors
        push!(df, vcat(combine(mid, UniqueID(size(df)[1]+1)), [desc[c] for c in colnames]))
    end
    return df
end

load_data(m::Type{<:AbstractDataModel}) = load_data(sourcefile(m), attributes(m), attributes_types(m), model(m))


load_fluids() = load_data(
    "fluid.json",
    ["name", "default_temperature", "max_temperature", "fuel_value", "emissions_multiplier"],
    [String, Int64, Int64, Int64, Int64],
    UniqueID(2)
)


items = load_data(Item)
replace!(x -> "fuel", filter(row -> row.fuel_value > 0, items; view=true).type)
filter(row -> row.type == "fuel", items)