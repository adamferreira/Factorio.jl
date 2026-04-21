#!/usr/bin/env julia
# Scrapes https://wiki.factorio.com for Factorio 2.0 (Space Age) data.
# Writes: data/factorio2_data.json
#
# Install required packages once:
#   julia -e 'using Pkg; Pkg.add(["HTTP", "Gumbo", "Cascadia", "JSON"])'
#
# Run from repo root:
#   julia data/scrape_wiki.jl

using HTTP, Gumbo, Cascadia, JSON, Dates
const sel = Cascadia.Selector

# ── Config ────────────────────────────────────────────────────────────────────

const WIKI_API = "https://wiki.factorio.com/api.php"
const HEADERS  = ["User-Agent" => "Factorio.jl/scraper (https://github.com/Factorio-jl)"]
const DELAY    = 0.5   # seconds between requests — be polite to the wiki

# Machines don't have a single wiki category; list them explicitly.
# Add or remove entries as Factorio 2.0 / Space Age DLC evolves.
const MACHINE_PAGES = [
    # Base game assemblers
    "Assembling machine 1", "Assembling machine 2", "Assembling machine 3",
    # Furnaces
    "Stone furnace", "Steel furnace", "Electric furnace",
    # Chemical / oil
    "Chemical plant", "Oil refinery",
    # Other base
    "Centrifuge", "Rocket silo",
    # Space Age DLC
    "Biochamber", "Cryogenic plant", "Electromagnetic plant", "Foundry",
]

const MODULE_PAGES = [
    "Speed module", "Speed module 2", "Speed module 3",
    "Productivity module", "Productivity module 2", "Productivity module 3",
    "Efficiency module", "Efficiency module 2", "Efficiency module 3",
    "Quality module", "Quality module 2", "Quality module 3",
]

# ── HTTP / API helpers ────────────────────────────────────────────────────────

function api_get(params::Dict{String,String})::Dict
    base = merge(Dict("format" => "json", "formatversion" => "2"), params)
    query = join((HTTP.escapeuri(k) * "=" * HTTP.escapeuri(v) for (k, v) in base), "&")
    sleep(DELAY)
    r = HTTP.get("$WIKI_API?$query", headers=HEADERS, status_exception=false)
    r.status == 200 || error("HTTP $(r.status) — query: $query")
    return JSON.parse(String(r.body))
end

function fetch_html(title::String)::HTMLDocument
    data = api_get(Dict("action" => "parse", "page" => title,
                        "prop" => "text", "disablelimitreport" => "1"))
    haskey(data, "error") && error("Wiki error for '$(title)': $(data["error"]["info"])")
    return parsehtml(data["parse"]["text"])
end

# ── Category enumeration ──────────────────────────────────────────────────────

# Returns all page titles in a category, following continuation tokens.
# Set recurse=true to also expand sub-category members one level deep.
function category_members(cat::String; recurse::Bool=false)::Vector{String}
    pages = String[]
    subcats = String[]

    params = Dict("action" => "query", "list" => "categorymembers",
                  "cmtitle" => "Category:$cat", "cmlimit" => "500",
                  "cmprop" => "title|type")
    while true
        data = api_get(params)
        for m in data["query"]["categorymembers"]
            if m["type"] == "page"
                push!(pages, m["title"])
            elseif m["type"] == "subcat" && recurse
                # strip "Category:" prefix
                push!(subcats, replace(m["title"], "Category:" => ""))
            end
        end
        haskey(data, "continue") || break
        params["cmcontinue"] = data["continue"]["cmcontinue"]
    end

    for sub in subcats
        append!(pages, category_members(sub; recurse=false))
    end

    return unique(pages)
end

# ── HTML traversal helpers ────────────────────────────────────────────────────

# Recursively collect all text under a node.
node_text(n::HTMLElement) = join(node_text(c) for c in children(n))
node_text(n::HTMLText)    = n.text
node_text(_)              = ""

trim_text(n) = strip(node_text(n))

# Return the first CSS match or nothing.
function first_match(selector, node)
    ms = eachmatch(sel(selector), node)
    isempty(ms) ? nothing : first(ms)
end

# ── Infobox row lookup ────────────────────────────────────────────────────────

# Finds a row in the infobox table by its label text and returns the value cell.
# For quality-tiered values (nested table), returns the Normal-quality (first) value.
function infobox_value(doc::HTMLDocument, label::String)::Union{String, Nothing}
    for row in eachmatch(sel("div.infobox tr"), doc.root)
        cells = eachmatch(sel("td, th"), row)
        length(cells) < 2 && continue
        strip(node_text(cells[1])) == label || continue

        val_cell = cells[2]
        # Check for a nested quality table (Factorio 2.0 quality tiers).
        # The first <tr> in that table holds: [colspan=2 spacer] [quality icon] [value].
        nested_rows = eachmatch(sel("table tr"), val_cell)
        if !isempty(nested_rows)
            tds = eachmatch(sel("td"), first(nested_rows))
            # Last <td> in the first row is the Normal-quality value.
            isempty(tds) || return strip(node_text(last(tds)))
        end

        return strip(node_text(val_cell))
    end
    return nothing
end

# ── Number parsers ────────────────────────────────────────────────────────────

function parse_num(s, default::Float64=0.0)::Float64
    s === nothing && return default
    # Strip units, rate suffixes (/m, /s), signs, and commas
    cleaned = replace(string(s), r"[kK][wW]" => "", r"[mM][wW]" => "e3",
                      "%" => "", "+" => "", "," => "", r"/[a-zA-Z]+" => "",
                      r"\s.*" => "")
    try parse(Float64, cleaned) catch; default end
end

parse_int(s, default::Int=0)::Int = try parse(Int, replace(string(s), r"[^\d]" => "")) catch; default end

# MW suffix means × 1000 kW — handled by "e3" substitution above.
function parse_energy_kw(s)::Float64
    s === nothing && return 0.0
    mw = occursin(r"[mM][wW]", s)
    v  = parse_num(s)
    return mw ? v * 1000.0 : v
end

# ── Recipe parser ─────────────────────────────────────────────────────────────

# wiki display name → internal kebab-case id  ("Iron plate" → "iron-plate")
wiki_to_id(name::AbstractString) = lowercase(replace(strip(name), " " => "-"))

struct Ingredient
    name::String
    type::String   # "item" or "fluid"
    amount::Float64
end

struct Product
    name::String
    type::String
    amount::Float64
    probability::Float64
end

struct Recipe
    crafting_time::Float64
    ingredients::Vector{Ingredient}
    products::Vector{Product}
end

# Parse a single recipe from an infobox-vrow-value cell.
# The cell's direct children are a mix of factorio-icon <div>s and text nodes
# (+, →). Time icon has <a href="/Time">, ingredients come before →, products after.
function parse_recipe_cell(cell::HTMLElement)::Union{Recipe, Nothing}
    time       = 1.0
    found_time = false
    ingredients = Ingredient[]
    products    = Product[]
    past_arrow  = false

    for child in children(cell)
        if child isa HTMLText
            text = child.text
            (occursin("→", text) || occursin("→", text)) && (past_arrow = true)
            continue
        end
        child isa HTMLElement || continue

        # Descend into wrapper divs that may contain factorio-icons
        icons = if get(attrs(child), "class", "") == "factorio-icon"
            [child]
        else
            eachmatch(sel("div.factorio-icon"), child)
        end

        for icon in icons
            link = first_match("a", icon)
            link === nothing && continue

            href  = get(attrs(link), "href",  "")
            title = get(attrs(link), "title", wiki_to_id(lstrip(href, '/')))
            name  = wiki_to_id(title)

            amount_el = first_match("div.factorio-icon-text", icon)
            amount    = amount_el !== nothing ? parse_num(trim_text(amount_el), 1.0) : 1.0

            if href == "/Time" || name == "time"
                time       = amount
                found_time = true
                continue
            end

            # Distinguish fluid by checking if href starts with known fluid names.
            # The wiki uses the same icon structure for both; we mark all as "item"
            # here and post-process based on the fluids dict after full scrape.
            if past_arrow
                push!(products, Product(name, "item", amount, 1.0))
            else
                push!(ingredients, Ingredient(name, "item", amount))
            end
        end
    end

    (isempty(ingredients) && isempty(products)) && return nothing
    return Recipe(time, ingredients, products)
end

# Returns all recipes found on a page.
# Only collects infobox-vrow-value cells that sit directly below a "Recipe" label row,
# skipping "Total raw" and other similar sections that use the same cell class.
function scrape_recipes(doc::HTMLDocument)::Vector{Recipe}
    recipes = Recipe[]

    # ── Infobox recipe rows ────────────────────────────────────────────────────
    for tab in eachmatch(sel("div.infobox table"), doc.root)
        rows = eachmatch(sel("tr"), tab)
        for (i, row) in enumerate(rows)
            tds = eachmatch(sel("td"), row)
            any(strip(node_text(td)) == "Recipe" for td in tds) || continue
            i + 1 > length(rows) && continue
            cell = first_match("td.infobox-vrow-value", rows[i+1])
            cell === nothing && continue
            r = parse_recipe_cell(cell)
            r !== nothing && push!(recipes, r)
        end
    end

    # ── Multi-recipe wikitable (e.g. Solid fuel, Barrel) ──────────────────────
    # Structure: table.wikitable with headers "Input" and "Output" columns.
    # Each data row is one recipe variant; Input holds time+ingredients, Output holds products.
    for tbl in eachmatch(sel("table.wikitable"), doc.root)
        header_row = first_match("tr", tbl)
        header_row === nothing && continue
        headers = [strip(node_text(h)) for h in eachmatch(sel("th"), header_row)]
        input_col  = findfirst(==("Input"),  headers)
        output_col = findfirst(==("Output"), headers)
        (input_col === nothing || output_col === nothing) && continue

        all_rows = eachmatch(sel("tr"), tbl)
        for row in all_rows[2:end]   # skip header
            cells = eachmatch(sel("td"), row)
            length(cells) < max(input_col, output_col) && continue

            # Collect all icons from a cell; returns (time, [(name,amount)...])
            function icons_in(cell)
                t = 1.0
                items = Tuple{String,Float64}[]
                for icon in eachmatch(sel("div.factorio-icon"), cell)
                    link = first_match("a", icon)
                    link === nothing && continue
                    href   = get(attrs(link), "href",  "")
                    title  = get(attrs(link), "title", wiki_to_id(lstrip(href, '/')))
                    name   = wiki_to_id(title)
                    amt_el = first_match("div.factorio-icon-text", icon)
                    amount = amt_el !== nothing ? parse_num(trim_text(amt_el), 1.0) : 1.0
                    if href == "/Time" || name == "time"
                        t = amount
                    else
                        push!(items, (name, amount))
                    end
                end
                return t, items
            end

            craft_time, ing_pairs = icons_in(cells[input_col])
            _, prod_pairs         = icons_in(cells[output_col])

            isempty(ing_pairs) && isempty(prod_pairs) && continue
            push!(recipes, Recipe(
                craft_time,
                [Ingredient(n, "item", a) for (n, a) in ing_pairs],
                [Product(n, "item", a, 1.0) for (n, a) in prod_pairs],
            ))
        end
    end

    return recipes
end

# ── Per-type scrapers ─────────────────────────────────────────────────────────

function scrape_item(title::String, doc::HTMLDocument)::Dict
    iname = infobox_value(doc, "Internal name")
    name  = iname !== nothing ? iname : wiki_to_id(title)
    return Dict{String,Any}(
        "name"         => name,
        "display_name" => title,
        "stack_size"   => parse_int(infobox_value(doc, "Stack size"), 50),
        "fuel_value"   => parse_num(infobox_value(doc, "Fuel value"), 0.0),
        "fuel_category" => infobox_value(doc, "Fuel category"),
        "type"         => "item",
    )
end

function scrape_fluid(title::String, doc::HTMLDocument)::Dict
    iname = infobox_value(doc, "Internal name")
    name  = iname !== nothing ? iname : wiki_to_id(title)
    return Dict{String,Any}(
        "name"                 => name,
        "display_name"         => title,
        "default_temperature"  => parse_num(infobox_value(doc, "Default temperature"), 15.0),
        "max_temperature"      => parse_num(infobox_value(doc, "Max temperature"), 100.0),
        "heat_capacity"        => parse_num(infobox_value(doc, "Heat capacity"), 0.2),
        "fuel_value"           => parse_num(infobox_value(doc, "Fuel value"), 0.0),
        "emissions_multiplier" => parse_num(infobox_value(doc, "Emissions multiplier"), 1.0),
        "type"                 => "fluid",
    )
end

# A page is a fluid if its "Prototype type" infobox row contains "fluid".
function is_fluid_page(doc::HTMLDocument)
    proto = infobox_value(doc, "Prototype type")
    return proto !== nothing && occursin("fluid", lowercase(proto))
end

function scrape_machine(title::String, doc::HTMLDocument)::Dict
    iname = infobox_value(doc, "Internal name")
    name  = iname !== nothing ? iname : wiki_to_id(title)

    # Crafting categories appear as a comma/newline-separated list or as individual
    # rows with label "Crafting categories" or "Crafting category".
    cat_label = something(infobox_value(doc, "Crafting categories"),
                          infobox_value(doc, "Crafting category"), "")
    cats = filter!(!isempty, strip.(split(cat_label, r",|\n")))

    return Dict{String,Any}(
        "name"               => name,
        "display_name"       => title,
        "type"               => "assembling-machine",
        "crafting_speed"     => parse_num(infobox_value(doc, "Crafting speed"), 1.0),
        "energy_usage_kw"    => parse_energy_kw(infobox_value(doc, "Energy consumption")),
        "pollution_per_min"  => parse_num(infobox_value(doc, "Pollution"), 0.0),
        "module_slots"       => parse_int(infobox_value(doc, "Module slots"), 0),
        "crafting_categories" => cats,
    )
end

function scrape_module(title::String, doc::HTMLDocument)::Dict
    iname = infobox_value(doc, "Internal name")
    name  = iname !== nothing ? iname : wiki_to_id(title)
    tier_m = match(r"\d+$", title)
    tier   = tier_m !== nothing ? parse(Int, tier_m.match) : 1

    return Dict{String,Any}(
        "name"         => name,
        "display_name" => title,
        "tier"         => tier,
        "effects"      => Dict{String,Any}(
            "speed"        => parse_num(infobox_value(doc, "Speed"),                0.0) / 100,
            "productivity" => parse_num(infobox_value(doc, "Productivity"),         0.0) / 100,
            "consumption"  => parse_num(infobox_value(doc, "Energy consumption"),   0.0) / 100,
            "pollution"    => parse_num(infobox_value(doc, "Pollution"),            0.0) / 100,
            "quality"      => parse_num(infobox_value(doc, "Quality"),              0.0) / 100,
        ),
    )
end

# ── Output helpers ────────────────────────────────────────────────────────────

function recipe_to_dict(r::Recipe, name::String)::Dict
    Dict{String,Any}(
        "name"          => name,
        "crafting_time" => r.crafting_time,
        "ingredients"   => [Dict("name" => i.name, "type" => i.type, "amount" => i.amount)
                             for i in r.ingredients],
        "products"      => [Dict("name" => p.name, "type" => p.type,
                                 "amount" => p.amount, "probability" => p.probability)
                             for p in r.products],
    )
end

# ── Main ──────────────────────────────────────────────────────────────────────

function main()
    out = Dict{String,Any}(
        "version"    => "2.0",
        "scraped_at" => string(today()),
        "items"      => Dict{String,Any}(),
        "fluids"     => Dict{String,Any}(),
        "recipes"    => Dict{String,Any}[],   # list — multiple recipes per product allowed
        "machines"   => Dict{String,Any}(),
        "modules"    => Dict{String,Any}(),
    )

    # ── Items & fluids (+ their recipes) ──────────────────────────────────────
    println("── Scraping intermediate products...")
    titles = category_members("Intermediate_products"; recurse=true)
    println("   Found $(length(titles)) pages")

    for title in titles
        @info "  $title"
        doc = try fetch_html(title)
        catch e
            @warn "  skip '$title': $e"
            continue
        end

        item_name = something(infobox_value(doc, "Internal name"), wiki_to_id(title))

        if is_fluid_page(doc)
            fluid = scrape_fluid(title, doc)
            out["fluids"][fluid["name"]] = fluid
        else
            item = scrape_item(title, doc)
            out["items"][item["name"]] = item
        end

        # Name infobox recipes after their product; wikitable recipes already have names set.
        recipes = scrape_recipes(doc)
        for (i, recipe) in enumerate(recipes)
            name = length(recipe.products) == 1 ? recipe.products[1].name :
                   length(recipe.products) > 1  ? join([p.name for p in recipe.products], "+") :
                   item_name
            # Avoid duplicate names when a page produces multiple recipe variants
            existing_names = Set(r["name"] for r in out["recipes"])
            name in existing_names && (name = "$(name)-$(i)")
            push!(out["recipes"], recipe_to_dict(recipe, name))
        end
    end

    # ── Fix fluid types in recipe ingredients/products ────────────────────────
    fluid_names = Set(keys(out["fluids"]))
    for recipe in out["recipes"]
        for ing in recipe["ingredients"]
            ing["name"] in fluid_names && (ing["type"] = "fluid")
        end
        for prod in recipe["products"]
            prod["name"] in fluid_names && (prod["type"] = "fluid")
        end
    end

    # ── Machines ──────────────────────────────────────────────────────────────
    println("── Scraping machines...")
    for title in MACHINE_PAGES
        @info "  $title"
        doc = try fetch_html(title) catch e; @warn "  skip '$title': $e"; continue end
        m = scrape_machine(title, doc)
        out["machines"][m["name"]] = m
    end

    # ── Modules ───────────────────────────────────────────────────────────────
    println("── Scraping modules...")
    for title in MODULE_PAGES
        @info "  $title"
        doc = try fetch_html(title) catch e; @warn "  skip '$title': $e"; continue end
        m = scrape_module(title, doc)
        out["modules"][m["name"]] = m
    end

    # ── Write output ──────────────────────────────────────────────────────────
    output_path = joinpath(@__DIR__, "factorio2_data.json")
    open(output_path, "w") do f
        JSON.print(f, out, 2)
    end

    println("\nDone → $output_path")
    println("  items:    $(length(out["items"]))")
    println("  fluids:   $(length(out["fluids"]))")
    println("  recipes:  $(length(out["recipes"])) ($(length(Set(r["name"] for r in out["recipes"]))) unique names)")
    println("  machines: $(length(out["machines"]))")
    println("  modules:  $(length(out["modules"]))")
end

main()
