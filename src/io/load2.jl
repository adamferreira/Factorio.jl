# Loader for data/factorio2_data.json — the Factorio 2.0 wiki-scraped dataset.
# Mirrors the API of load.jl but reads from the single combined JSON file
# produced by data/scrape_wiki.jl.
#
# Unit / field mapping versus the old per-file JSON format:
#   crafting_time  (new) → crafttime        (struct)
#   energy_usage_kw× 1000 (new, kW) → energy_usage (struct, W)
#   module_slots   (new) → module_inventory_size (struct)
#   effects.X      (new) → X                (Module struct fields)
#   amounts are Float64  (new) vs Int64     (old) — struct updated accordingly

const DATA2_FILE = joinpath(@__DIR__, "..", "..", "data", "factorio2_data.json")

# Base.get is shadowed by DataModel.get — use an explicit alias throughout this file.
const dget = Base.get

function load_factorio2_json()::Dict
    isfile(DATA2_FILE) || error("factorio2_data.json not found — run data/scrape_wiki.jl first")
    return JSON.parsefile(DATA2_FILE)
end

# Items
function load2_items()::DataFrame
    raw  = load_factorio2_json()
    mid  = model(Item)
    cols = fieldnames(Item)
    types = fieldtypes(Item)
    df   = DataFrame(vcat(:uid => UniqueID[], [(n => t[]) for (n, t) in zip(cols, types)]))

    for (_, desc) in raw["items"]
        uid  = combine(mid, UniqueID(nrow(df) + 1))
        type = desc["fuel_value"] > 0 ? "fuel" : dget(desc, "type", "item")
        push!(df, (
            uid,
            desc["name"],
            -1,                              # tier — computed later by factorio_init
            type,
            Float64(desc["fuel_value"]),
            Int64(dget(desc, "stack_size", 50)),
        ))
    end
    return df
end

# Fluids
function load2_fluids()::DataFrame
    raw  = load_factorio2_json()
    mid  = model(Fluid)
    cols = fieldnames(Fluid)
    types = fieldtypes(Fluid)
    df   = DataFrame(vcat(:uid => UniqueID[], [(n => t[]) for (n, t) in zip(cols, types)]))

    for (_, desc) in raw["fluids"]
        uid = combine(mid, UniqueID(nrow(df) + 1))
        push!(df, (
            uid,
            desc["name"],
            Int64(round(dget(desc, "default_temperature", 15.0))),
            Int64(round(dget(desc, "max_temperature",     100.0))),
            Float64(dget(desc, "fuel_value",           0.0)),
            Float64(dget(desc, "emissions_multiplier", 1.0)),
        ))
    end
    return df
end

# Recipes
function load2_recipes()::DataFrame
    raw  = load_factorio2_json()
    mid  = model(Recipe)
    cols = fieldnames(Recipe)
    types = fieldtypes(Recipe)
    df   = DataFrame(vcat(:uid => UniqueID[], [(n => t[]) for (n, t) in zip(cols, types)]))

    # New format: recipes is a list, not a dict.
    # Category is not scraped from the wiki — default to "crafting".
    # Amounts are Float64 to support fractional recycler outputs.
    for desc in raw["recipes"]
        isempty(desc["products"]) && continue   # skip fill/empty barrel stubs
        uid = combine(mid, UniqueID(nrow(df) + 1))
        push!(df, (
            uid,
            desc["name"],
            -1,                              # tier
            dget(desc, "category", "crafting"),
            Float64(desc["crafting_time"]),
            String[ing["name"] for ing in desc["ingredients"]],
            Float64[ing["amount"] for ing in desc["ingredients"]],
            String[p["name"] for p in desc["products"]],
            Float64[p["amount"] for p in desc["products"]],
            Float64[dget(p, "probability", 1.0) for p in desc["products"]],
        ))
    end
    return df
end

# Assembling machines
function load2_machines()::DataFrame
    raw  = load_factorio2_json()
    mid  = model(AssemblingMachine)
    cols = fieldnames(AssemblingMachine)
    types = fieldtypes(AssemblingMachine)
    df   = DataFrame(vcat(:uid => UniqueID[], [(n => t[]) for (n, t) in zip(cols, types)]))

    for (_, desc) in raw["machines"]
        uid = combine(mid, UniqueID(nrow(df) + 1))
        push!(df, (
            uid,
            desc["name"],
            Float64(dget(desc, "crafting_speed",    1.0)),
            Float64(dget(desc, "energy_usage_kw",   0.0)) * 1000.0,  # kW → W
            Float64(dget(desc, "pollution_per_min", 0.0)),
            Int64(dget(desc, "module_slots",        0)),
            String[c for c in dget(desc, "crafting_categories", String[])],
        ))
    end
    return df
end

# ── Modules ───────────────────────────────────────────────────────────────────

function load2_modules()::DataFrame
    raw  = load_factorio2_json()
    mid  = model(Module)
    cols = fieldnames(Module)
    types = fieldtypes(Module)
    df   = DataFrame(vcat(:uid => UniqueID[], [(n => t[]) for (n, t) in zip(cols, types)]))

    for (_, desc) in raw["modules"]
        uid     = combine(mid, UniqueID(nrow(df) + 1))
        effects = dget(desc, "effects", Dict{String,Any}())
        push!(df, (
            uid,
            desc["name"],
            Float64(dget(effects, "consumption",  0.0)),
            Float64(dget(effects, "speed",        0.0)),
            Float64(dget(effects, "productivity", 0.0)),
            Float64(dget(effects, "pollution",    0.0)),
        ))
    end
    return df
end



function factorio2_init()
    # Step 1: Parse all data model tables
    models = [DataFrame() for _ in datamodels()]
    models[model(Item)]              = load2_items()
    models[model(Recipe)]            = load2_recipes()
    models[model(Fluid)]             = load2_fluids()
    models[model(AssemblingMachine)] = load2_machines()
    models[model(Module)]            = load2_modules()

    # Step 2: Create DB with an empty recipe graph
    db = DefaultFactorioDataBase(models, RecipeGraph(nothing), zeros(1, 1))
    db.recgraph = RecipeGraph(db)

    # Step 2.5: Mirror fluids into the Item table so they can appear as ingredients
    for f in eachrow(data(Fluid, db))
        uid = combine(model(Item), UniqueID(nrow(data(Item, db)) + 1))
        push!(data(Item, db), [uid, f.name, -1, "fluid", f.fuel_value, 0])
    end

    # Step 3: Build the recipe graph
    # Add every item (including fluid aliases) as a potential ingredient node
    for uid in data(Item, db).uid
        add_recipe_node!(db.recgraph, RecipeGraphNode(uid))
    end

    # Lookup helper — returns nothing when a name is absent from both tables
    function try_get(name::AbstractString)
        for T in (Item, Fluid)
            rows = filter(row -> row.name == name, data(T, db); view=true)
            isempty(rows) || return rows[1, :]
        end
        return nothing
    end

    for r in eachrow(data(Recipe, db))
        ings  = [try_get(n) for n in r.ingredients_names]
        prods = [try_get(n) for n in r.products_names]
        # Skip recipes that reference items not present in the scraped data
        (any(isnothing, ings) || any(isnothing, prods)) && continue

        add_recipe_node!(db.recgraph, RecipeGraphNode(r.uid))
        for (ing, amt) in zip(ings, r.ingredients_amounts)
            add_recipe_edge!(db.recgraph, ing.uid, r.uid, RecipeGraphEdge(amt, 1.0))
        end
        for (prod, amt, prob) in zip(prods, r.products_amounts, r.products_probabilities)
            add_recipe_edge!(db.recgraph, r.uid, prod.uid, RecipeGraphEdge(amt, prob))
        end
    end

    # Step 4: Compute tiers
    # 4.1 — raw materials: no inbound edges, at least one outbound edge
    raws = filter(v -> Graphs.indegree(db.recgraph, v) == 0 && Graphs.outdegree(db.recgraph, v) >= 1,
                  Graphs.vertices(db.recgraph))
    for code in raws
        get(MetaGraphsNext.label_for(db.recgraph, code), db).tier = 0
    end

    # 4.2 — remove edges that form cycles (e.g. recycler loops)
    for c in Graphs.simplecycles(db.recgraph)
        MetaGraphsNext.rem_edge!(db.recgraph, c[1], c[2])
    end

    # 4.3 — propagate tier numbers recursively
    tiers = zeros(Graphs.nv(db.recgraph)) .- 1
    function compute_tier(code)::Int64
        tiers[code] > -1 && return Int64(tiers[code])
        if Graphs.indegree(db.recgraph, code) == 0 && Graphs.outdegree(db.recgraph, code) >= 1
            tiers[code] = 0
            return 0
        end
        parents = MetaGraphsNext.inneighbors(db.recgraph, code)
        isempty(parents) && return -1
        t = reduce(max, compute_tier.(parents))
        label = MetaGraphsNext.label_for(db.recgraph, code)
        tiers[code] = model(label) == model(Recipe) ? t + 1 : t
        return Int64(tiers[code])
    end
    for v in filter(v -> Graphs.indegree(db.recgraph, v) > 0, Graphs.vertices(db.recgraph))
        compute_tier(v)
    end
    for code in Graphs.vertices(db.recgraph)
        get(MetaGraphsNext.label_for(db.recgraph, code), db).tier = Int64(tiers[code])
    end

    # Step 5: Pairwise recipe similarity distances
    db.distmtx = recipe_distance(db)
    return db
end
