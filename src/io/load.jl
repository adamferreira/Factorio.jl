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

function load_fluids()::DataFrame
    # Default column parsing lambdas
    parsecol = parsecol_fct(Fluid)
    return load_data(Fluid, parsecol)
end

function load_machines()::DataFrame
    # Default column parsing lambdas
    parsecol = parsecol_fct(AssemblingMachine)
    parsecol[:crafting_categories] = desc -> collect(keys(desc["crafting_categories"]))
    return load_data(AssemblingMachine, parsecol)
end

function load_modules()::DataFrame
    # Default column parsing lambdas
    parsecol = parsecol_fct(Module)
    # Callback to get Module attributes from item datafile
    for c in [:consumption, :speed, :productivity, :pollution]
        parsecol[c] = desc -> begin
            if "module_effects" in keys(desc) && String(c) in keys(desc["module_effects"])
                return desc["module_effects"][String(c)]["bonus"]
            else
                return 0.
            end
        end 
    end
    # Remove non-modules item loaded from item.json
    return filter(row -> occursin("-module", row.name), load_data(Module, parsecol))
end