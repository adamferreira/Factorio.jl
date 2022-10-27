
abstract type AbstractElement end
abstract type AbstractDataModel end

abstract type AbstractItem <: AbstractElement end
abstract type Fluid <: AbstractItem end
abstract type Item <: AbstractItem end

abstract type Energy end
abstract type Fuel <: Energy end
abstract type Electricity <: Energy end


# Type Logic
#EnergyConsumer = Union{Asset, Item}


# DataModel Holding Everything Needed
abstract type FactorioDataBase end

const Tier = UInt16
# An Asset is an object that can be defined by different tiers and can be placed down in the game
# Example: AssemblingMachine1, AssemblingMachine2, etc...
# Or: Stone Furnace, Electric Furnace
# The tier of an asset can be retrived from the template value of the 'Asset' struct
abstract type Asset{T} <: AbstractElement end
# An AssetDataModel is an AbstractDataModel that stores tiers information with vectors
# Each indexes of the vectors represents a Tier
#abstract type AssetDataModel <: AbstractDataModel end
Asset(x) = Asset{x}()
tier(::Asset{T}) where T = T

# Macro to easily define new assets
macro asset(AssetType)
    return quote
        struct $AssetType{T} <: Asset{T}
            database::FactorioDataBase
        end
        #$AssetType(x) = $AssetType{x}()
        $AssetType(x,m) = $AssetType{x}(m)
    end |> esc
end

# --------------
# Data Models
# --------------
database(x::Asset) = x.database # DEFAULT_DATABASE
# Every DataModel should have the files ::names
name(x::Asset) = database(x).names[tier(x)]

# DataModel for AssemblingMachines 
@asset AssemblingMachine
struct AssemblingMachines <: AbstractDataModel # -> Object Model ?
    # Mapping names to asset types
    #mapping::Dict{String, AssemblingMachine}
    # Names
    names::Vector{String}
    # Electric consumption
    elec_consumptions::Vector{Float64}
    # Fuel consumption
    fuel_consumptions::Vector{Float64}
    # Pollution Generation
    pollution::Vector{Float64}
end


# DataModel Holding Everything Needed
struct DefaultFactorioDataBase <: FactorioDataBase
    assembling_machines::AssemblingMachines
    DefaultFactorioDataBase() = new(
        load_assembling_machines()
    )
end

# Define mapping between elements (asset, items, ...) and their data model
@inline model(m::DefaultFactorioDataBase, x::AssemblingMachine)::AbstractDataModel = m.assembling_machines


# Default consumption for any DataModel and Any Asset
consumption(::Type{<:Energy}, x::Asset) = 0.0

consumption(::Type{Electricity}, x::AssemblingMachine) =  model(database(x), x).elec_consumptions[tier(x)]
consumption(::Type{Fuel}, x::AssemblingMachine) = model(database(x), x).fuel_consumptions[tier(x)]