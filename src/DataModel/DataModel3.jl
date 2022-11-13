abstract type AbstractElement end
abstract type AbstractDataModel end

abstract type Energy end
abstract type Fuel <: Energy end
abstract type Electricity <: Energy end

# DataModel Holding Everything Needed
abstract type FactorioDataBase end

const UniqueID = UInt16

"""
    Concatenates the two hashes `a` and `b` into `T`.
    Let's sya T = UInt8 and:
    - a = 10 = 00001010
    - b = 12 = 00001100
    This function returns the new hash 10100000 | 00001100 = 10101100
"""
function combine(a::T, b::T) where {T<:Unsigned}
    return (a << (4*sizeof(T))) | (b & mask(T))
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
    For example let r be the 4th Recipe (ussuming UInt8 indextypes).
    model(r) = model(Recipe) = 1 = 00000001
    index(r) = 4 = 00000100
    uid(r) = 00010100
    Thus given an uid, it is possible to deduce its datamodel and its specific values within the datamodel
"""
MODELS = [
    :Recipe,
    :Technology,
    :Item,
    :AssemblingMachine,
    :Resource,
    :Asset
]

"""
    A recipe is an element that have a crafting Time.
    And is meant to be used in a Recipe Graph.
"""
struct Recipe <: AbstractDataModel
    ind::UniqueID
    name::String
    craftime::Float64
end

"""
    A Technology is an element that unlocks other elements.
    And is meant to be used in a Technology Graph.
"""
struct Technology <: AbstractDataModel
    ind::UniqueID
    name::String
end

"""
    An item is an element that can be inside and inventory, be crafted, or be unlocked.
"""
struct Item <: AbstractDataModel
    ind::UniqueID
    name::String
end

"""
    An AssemblingMachine is an element that can craft Items/Resources from Items/Resources
"""
struct AssemblingMachine <: AbstractDataModel
    ind::UniqueID
    name::String
    craftspeed::Float64
end

struct Resource <: AbstractDataModel
    ind::UniqueID
    name::String
end

"""
    An asset is an element that can be placed down in the game.
    And is meant to be used in a Network to simulate the game.
"""
struct Asset <: AbstractDataModel
    ind::UniqueID
    name::String
end 


# Define UniqueIds methods on all variant of `AbstractDataModel`
for (id, m) in enumerate(MODELS)
    @eval model(x::$m) = UniqueID($id)
    @eval index(x::$m) = UniqueID(x.ind)
    @eval uid(x::$m) = UniqueID(combine(model(x), index(x)))
end


struct DefaultFactorioDataBase <: FactorioDataBase
    #recipes::Dict{String, Recipe}
    #items::Dict{String, Item}
    #resources::Dict{String, Resource}
    #technologies::Dict{String, Technology}
    # Stores datamodel as an ArrayOfStruct fashion
    recipes::Vector{Recipe}

    # Map AbstractDataModel name to their model indexes
    recipes_mapping::Dict{String, UniqueID}
end

function add_recipe!(d::FactorioDataBase, name::String, craftime::Float64)
    # Check of recipe does not already exits
    @assert !haskey(d.recipes_mapping, name)
    # Register new recipe
    r = Recipe(UniqueID(length(d.recipes)+1), name, craftime)
    push!(d.recipes, r)
    d.recipes_mapping[name] = index(r)
end

function get_recipe(x::String)
    return d.recipes[d.recipes_mapping[x]]
end

function get_recipe(x::UniqueID)
    return d.recipes[index(x)]
end


"""
    Get a refence to Factorio's default database (type DefaultFactorioDataBase)
"""
database() = FACTORIO_DEFAULT_DB

d = DefaultFactorioDataBase([], Dict())
add_recipe!(d, "Recipe1", 1.05)
ind = d.recipes_mapping["Recipe1"]
r = d.recipes[ind]
@show bitstring(index(r))
@show bitstring(model(r))
@show bitstring(uid(r))
@show get_recipe(uid(r))
@time for i in 1:1000000 get_recipe(uid(r)) end