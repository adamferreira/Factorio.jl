abstract type AbstractElement end
abstract type AbstractDataModel end

abstract type Energy end
abstract type Fuel <: Energy end
abstract type Electricity <: Energy end

# DataModel Holding Everything Needed
abstract type FactorioDataBase end

"""
    A Factorio element is a UniqueElement.
    It has a unique identifider (Interger) that encodes:
    - The index of its model
    - Its index in its model's data array
    Thus given a UniqueElement, you can know its model (type) and as direct constant access to its data
"""
const ElementHash = UInt16
struct UniqueElement{M,T<:Unsigned} <: AbstractElement
    # TODO: have model_id in UInt16 and uid as UInt16 ?
    uid::T
end

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

UniqueElement(mid::M, id::T) where {M,T<:Unsigned} = UniqueElement{M,T}(combine(T(mid), id))
@inline uid(x::UniqueElement{M,T}) where {M,T<:Unsigned} = x.uid

"""
    The mask for an Integer type `T` stored in n bits is
    n/2 `0` bits followed by n/2 `1` bits
    The mask for UInt8 is `00001111`
"""
@inline mask(::Type{T}) where {T<:Unsigned} = T((1 << (4*sizeof(T))) - 1)
"""
    Get the last |`T`|/2 bits of the uid
"""
@inline index(x::UniqueElement{M,T}) where {M,T<:Unsigned} = uid(x) & mask(T)
"""
    Get the first |`T`|/2 bits of the uid
"""
@inline model(x::UniqueElement{M,T}) where {M,T<:Unsigned} = (~mask(T) & uid(x)) >> T(4*sizeof(T))


MODELS = [
    # A recipe is an element that have a crafting Time.
    # And is meant to be used in a Recipe Graph.
    :Recipe,
    # An asset is an element that can be placed down in the game.
    # And is meant to be used in a Network to simulate the game.
    :Asset,
    # A recipe is an element that unlocks other elements.
    # And is meant to be used in a Technology Graph.
    :Technology,
    # An item is an element that can be inside and inventory, be crafted, or be unlocked.
    :Item
]
# Define implementations of UniqueElement
# Recipe is UniqueElement{1,T} for example
for p in enumerate(MODELS)
    # Define type alias
    @eval const $(p[2]) = UniqueElement{ElementHash($(p[1])), ElementHash}
    # Contructor from id (will combine with this type id)
    @eval $(p[2])(id) = UniqueElement(ElementHash($(p[1])), ElementHash(id))
end

# Model Holding data (in tabular form) for efficiency purposes
struct Items <: AbstractDataModel
    # Names of the Item
    names::Vector{String}
end

"""
    Get the name of an UniqueElement from its data model array 'names'.
    This assumes that the datamodel encoded in `model(x)` has a field names::names::Vector{T}
"""
@inline name(x::UniqueElement) = @inbounds datamodel(x).names[index(x)]




# DataModel Holding Everything Needed
struct DefaultFactorioDataBase <: FactorioDataBase
    datamodels::Vector{AbstractDataModel}
end
"""
    Get the datamodel of the a unique element from the gobal database using its model_id.
"""
@inline datamodel(x::UniqueElement) = @inbounds database().datamodels[model(x)]


"""
a = UniqueElement(10, UInt8(12))
@show bitstring(uid(a))
@show bitstring(model(a))
@show bitstring(index(a))
@show bitstring(mask(UInt8))
@show bitstring(~mask(UInt8))
"""