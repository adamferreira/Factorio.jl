using DataFrames
using JSON

DATA_DIR = joinpath(@__DIR__, "..", "..", "data")

# Override convertion from 2-tuple to pair
# Used to transform a list of tuples to a list of pairs in load_data
Base.convert(::Type{Pair}, t::Tuple{A,B}) where {A,B} = Pair{A,B}(t[1], t[2])

function load_data(filename::AbstractString, colnames::Vector{<:AbstractString}, coltypes::Vector{DataType})::DataFrame
    # Load the json datafile as a dictionnary
    d = JSON.parsefile(joinpath(DATA_DIR, filename))
    # Id of the given element relative to filename
    id = 1
    # Prepare empty DataFrame with appropriate column names and types
    # Also ad the "id" Int64 column
    # df = DataFrame(vcat("id" => Int64[], [(c => []) for c in cols]...))
    df = DataFrame(vcat("id" => Int64[], [(n => t[]) for (n,t) in zip(colnames, coltypes)]))
    # Iterate over dict `d` content
    for (name, desc) in d
        # Append DataFrame row-with_neighbors
        push!(df, vcat(id, [desc[c] for c in colnames]))
        id += 1
    end
    return df
end


load_items() = load_data(
    "item.json",
    ["name", "type", "fuel_value", "stack_size"],
    [String, String, Int64, Int64]
)
load_fluids() = load_data(
    "fluid.json",
    ["name", "default_temperature", "max_temperature", "fuel_value", "emissions_multiplier"],
    [String, Int64, Int64, Int64, Int64]
)


items = load_items()
replace!(x -> "fuel", filter(row -> row.fuel_value > 0, items; view=true).type)
filter(row -> row.type == "fuel", items)