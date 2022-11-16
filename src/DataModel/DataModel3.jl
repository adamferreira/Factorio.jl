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


name(x::AbstractDataModel) = x.name

# Define UniqueIds methods on all variant of `AbstractDataModel`
for (id, m) in enumerate(MODELS)
    @eval @inline model(x::$m) = UniqueID($id)
    @eval @inline index(x::$m) = x.ind
    @eval @inline uid(x::$m) = combine(model(x), index(x))
end


struct DefaultFactorioDataBase <: FactorioDataBase
    # (Do not use a vector of vector{AbstractDataModel} as get[model] would return a vector and thus an allocation)
    # Stores datamodel as an ArrayOfStruct fashion
    # TODO : only store Recipe info in the recipe graph ?
    recipes::Vector{Recipe}
    items::Vector{Item}
    resources::Vector{Resource}
    technologies::Vector{Technology}

    # Map AbstractDataModel name to their model indexes
    mappings::Vector{Dict{String, UniqueID}}

end

function DefaultFactorioDataBase()
    recipes = Vector{Recipe}()
    items = Vector{Item}()
    resources = Vector{Resource}()
    technologies = Vector{Technology}()
    return DefaultFactorioDataBase(
        recipes, items, resources, technologies,
        [Dict(), Dict(), Dict(), Dict()]
    )
end

recipes_mapping(d::FactorioDataBase) = d.mappings[1]


function add!(d::FactorioDataBase, ::Type{T}, args...) where {T<:AbstractDataModel}
    # Check if datamodel does not already exits
    @assert !haskey(recipes_mapping(d), name)
    model = d.recipes
end

function add_recipe!(d::FactorioDataBase, name::String, craftime::Float64)
    # Check of recipe does not already exits
    @assert !haskey(recipes_mapping(d), name)
    # Register new recipe
    r = Recipe(UniqueID(length(d.recipes)+1), name, craftime)
    push!(d.recipes, r)
    recipes_mapping(d)[name] = index(r)
end

"""
    Getter for specific DataModel types
    Returns an AbstractDataModel
"""
get(d::DefaultFactorioDataBase, ::Val{1}, x::UniqueID) = d.recipes[index(x)]
get(d::DefaultFactorioDataBase, ::Val{3}, x::UniqueID) = d.items[index(x)]
get(d::DefaultFactorioDataBase, ::Val{4}, x::UniqueID) = d.resources[index(x)]
get(d::DefaultFactorioDataBase, ::Val{5}, x::UniqueID) = d.technologies[index(x)]

get(d::DefaultFactorioDataBase, ::Type{Recipe}, x::UniqueID) = d.recipes[index(x)]
get(d::DefaultFactorioDataBase, ::Type{Item}, x::UniqueID) = d.items[index(x)]
get(d::DefaultFactorioDataBase, ::Type{Resource}, x::UniqueID) = d.resources[index(x)]
get(d::DefaultFactorioDataBase, ::Type{Technology}, x::UniqueID) = d.technologies[index(x)]

"""
    Getter with DataModel value type deduction
    Returns an AbstractDataModel
"""
get(d::DefaultFactorioDataBase, x::UniqueID) = get(d, TOTO[model(x)], x)


TOTO = [Recipe]

"""
    Get a refence to Factorio's default database (type DefaultFactorioDataBase)
"""
database() = FACTORIO_DEFAULT_DB

d = DefaultFactorioDataBase()
add_recipe!(d, "Recipe1", 1.05)
ind = recipes_mapping(d)["Recipe1"]
r = d.recipes[ind]
@show bitstring(index(r))
@show bitstring(model(r))
@show bitstring(uid(r))
@show get(d, uid(r))
@show typeof(get(d, Val(1), uid(r)))

@time for i in 1:1000000 get(d, Val(1), uid(r)) endd
@time for i in 1:1000000 name(r) end
@time for i in 1:1000000 name(get(d, uid(r))) end
@time for i in 1:1000000 model(uid(r)) end