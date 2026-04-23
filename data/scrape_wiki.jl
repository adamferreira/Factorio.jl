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

const PLANET_PAGES = ["Nauvis", "Vulcanus", "Gleba", "Fulgora", "Aquilo"]

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

# Wiki thumbnail URLs look like /images/thumb/Iron_plate.png/32px-Iron_plate.png.
# Strip the /thumb/ segment and the sizing suffix to get the full-resolution URL.
function normalize_icon_url(src::String, base::String="https://wiki.factorio.com")::String
    full = startswith(src, "http") ? src : base * src
    # /images/thumb/Foo.png/32px-Foo.png → /images/Foo.png
    full = replace(full, r"/thumb(/[^/]+\.(?:png|gif|svg|webp))/[^/]+" => s"\1")
    return full
end

# Return the full-resolution icon URL for the entity shown on this page,
# by looking for the first <img> inside the infobox header or a factorio-icon div.
function infobox_icon_url(doc::HTMLDocument)::Union{String,Nothing}
    for css in ("div.infobox-header img", "div.infobox div.factorio-icon img", "div.infobox img")
        el = first_match(css, doc.root)
        el === nothing && continue
        src = get(attrs(el), "src", "")
        isempty(src) && continue
        return normalize_icon_url(src)
    end
    return nothing
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

# wiki display name → internal kebab-case id  ("Iron plate" → "iron-plate", "Fluoroketone (cold)" → "fluoroketone-cold")
wiki_to_id(name::AbstractString) = lowercase(replace(strip(name), r"[()]" => "", " " => "-"))

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
    name::String            # proper recipe name from wikitable Process column; "" for infobox recipes
    icon_url::String        # process icon URL; "" means fall back to primary product icon
    crafting_time::Float64
    ingredients::Vector{Ingredient}
    products::Vector{Product}
    made_in::Vector{String} # machine internal names, e.g. ["foundry"]
end

# Extract machine names from a "Made in" / "Produced by" cell or row —
# returns internal ids of every machine linked via <a title="…">.
function machines_in(node::HTMLElement)::Vector{String}
    machines = String[]
    for icon in eachmatch(sel("div.factorio-icon"), node)
        for a in eachmatch(sel("a"), icon)
            title = get(attrs(a), "title", "")
            isempty(title) || push!(machines, wiki_to_id(title))
        end
    end
    return unique(machines)
end

# Parse a single recipe from an infobox-vrow-value cell.
# The cell's direct children are a mix of factorio-icon <div>s and text nodes
# (+, →). Time icon has <a href="/Time">, ingredients come before →, products after.
# made_in is supplied by the caller (from the surrounding "Produced by" row).
function parse_recipe_cell(cell::HTMLElement, made_in::Vector{String}=String[], icon_url::String="")::Union{Recipe, Nothing}
    time        = 1.0
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
                time = amount
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
    return Recipe("", icon_url, time, ingredients, products, made_in)
end

# Returns all recipes found on a page, each with name and made_in populated.
function scrape_recipes(doc::HTMLDocument)::Vector{Recipe}
    recipes = Recipe[]

    # ── Infobox recipe rows ────────────────────────────────────────────────────
    # The "Produced by" row lists all machines that can craft this item via the
    # main recipe shown in the infobox.
    all_infobox_rows = collect(eachmatch(sel("div.infobox tr"), doc.root))
    infobox_made_in  = String[]
    for (i, row) in enumerate(all_infobox_rows)
        cells = eachmatch(sel("td, th"), row)
        isempty(cells) && continue
        strip(node_text(cells[1])) == "Produced by" || continue
        i + 1 <= length(all_infobox_rows) && append!(infobox_made_in, machines_in(all_infobox_rows[i+1]))
        break
    end

    for tab in eachmatch(sel("div.infobox table"), doc.root)
        rows = eachmatch(sel("tr"), tab)
        for (i, row) in enumerate(rows)
            tds = eachmatch(sel("td"), row)
            any(strip(node_text(td)) == "Recipe" for td in tds) || continue
            i + 1 > length(rows) && continue
            cell = first_match("td.infobox-vrow-value", rows[i+1])
            cell === nothing && continue
            r = parse_recipe_cell(cell, infobox_made_in)
            r !== nothing && push!(recipes, r)
        end
    end

    # ── Multi-recipe wikitable ─────────────────────────────────────────────────
    # Columns: Process (recipe name) | Input (time+ings) | Output (products) | Made in | …
    for tbl in eachmatch(sel("table.wikitable"), doc.root)
        header_row = first_match("tr", tbl)
        header_row === nothing && continue
        headers    = [strip(node_text(h)) for h in eachmatch(sel("th"), header_row)]
        input_col  = findfirst(==("Input"),   headers)
        output_col = findfirst(==("Output"),  headers)
        (input_col === nothing || output_col === nothing) && continue

        process_col = findfirst(==("Process"), headers)
        madein_col  = findfirst(==("Made in"), headers)

        # Collect icons (time + named items) from a recipe cell.
        function icons_in(cell)
            t = 1.0; items = Tuple{String,Float64}[]
            for icon in eachmatch(sel("div.factorio-icon"), cell)
                link = first_match("a", icon)
                link === nothing && continue
                href   = get(attrs(link), "href",  "")
                title  = get(attrs(link), "title", wiki_to_id(lstrip(href, '/')))
                name   = wiki_to_id(title)
                amt_el = first_match("div.factorio-icon-text", icon)
                amount = amt_el !== nothing ? parse_num(trim_text(amt_el), 1.0) : 1.0
                href == "/Time" || name == "time" ? (t = amount) : push!(items, (name, amount))
            end
            return t, items
        end

        for row in eachmatch(sel("tr"), tbl)[2:end]   # skip header
            cells = eachmatch(sel("td"), row)
            length(cells) < max(input_col, output_col) && continue

            craft_time, ing_pairs = icons_in(cells[input_col])
            _,          prod_pairs = icons_in(cells[output_col])
            isempty(ing_pairs) && isempty(prod_pairs) && continue

            # Recipe name and icon from Process column.
            # Name: text node directly inside the <td>, after the factorio-icon div.
            # Icon: the <img src> inside the factorio-icon div.
            recipe_name = ""; recipe_icon = ""
            if process_col !== nothing && process_col <= length(cells)
                pcell = cells[process_col]
                recipe_name = wiki_to_id(strip(join(
                    c.text for c in children(pcell) if c isa HTMLText
                )))
                img = first_match("div.factorio-icon img", pcell)
                if img !== nothing
                    src = get(attrs(img), "src", "")
                    isempty(src) || (recipe_icon = normalize_icon_url(src))
                end
            end

            # Machines from Made in column.
            made_in = String[]
            if madein_col !== nothing && madein_col <= length(cells)
                append!(made_in, machines_in(cells[madein_col]))
            end

            push!(recipes, Recipe(
                recipe_name,
                recipe_icon,
                craft_time,
                [Ingredient(n, "item", a) for (n, a) in ing_pairs],
                [Product(n, "item", a, 1.0) for (n, a) in prod_pairs],
                made_in,
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
        "icon_url"     => infobox_icon_url(doc),
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
        "icon_url"             => infobox_icon_url(doc),
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

    # "Crafted only on" row: icon-only links → planet names (e.g. ["vulcanus"])
    crafted_on = String[]
    crafted_on_cell = infobox_value_node(doc, "Crafted only on")
    if crafted_on_cell !== nothing
        for a in eachmatch(sel("a"), crafted_on_cell)
            t = get(attrs(a), "title", "")
            t == "Space Age" && continue
            isempty(t) || push!(crafted_on, wiki_to_id(t))
        end
    end

    return Dict{String,Any}(
        "name"               => name,
        "display_name"       => title,
        "icon_url"           => infobox_icon_url(doc),
        "type"               => "assembling-machine",
        "crafting_speed"     => parse_num(infobox_value(doc, "Crafting speed"), 1.0),
        "energy_usage_kw"    => parse_energy_kw(infobox_value(doc, "Energy consumption")),
        "pollution_per_min"  => parse_num(infobox_value(doc, "Pollution"), 0.0),
        "module_slots"       => parse_int(infobox_value(doc, "Module slots"), 0),
        "crafting_categories" => cats,
        "crafted_on"         => crafted_on,
    )
end

# Return the value cell element (not just text) for an infobox label — used when
# the cell contains nested icons that need to be traversed directly.
function infobox_value_node(doc::HTMLDocument, label::String)::Union{HTMLElement,Nothing}
    for row in eachmatch(sel("div.infobox tr"), doc.root)
        cells = eachmatch(sel("td, th"), row)
        length(cells) < 2 && continue
        strip(node_text(cells[1])) == label || continue
        return cells[2]
    end
    return nothing
end

function scrape_technology(page_title::String, doc::HTMLDocument)::Dict
    iname = infobox_value(doc, "Internal name")
    name  = iname !== nothing ? iname :
            wiki_to_id(replace(page_title, r"\s*\(research\)\s*$" => ""))

    time_per_unit   = 60.0
    research_units  = 0
    sci_ingredients = Pair{String,Float64}[]
    prerequisites   = String[]
    effects         = String[]

    # Technology infoboxes use a two-row pattern: one row holds the label (th/td),
    # the *next* row holds the content in a colspan="2" infobox-vrow-value cell.
    all_rows = collect(eachmatch(sel("div.infobox tr"), doc.root))
    for (i, row) in enumerate(all_rows)
        cells = eachmatch(sel("td, th"), row)
        isempty(cells) && continue
        label = strip(node_text(cells[1]))
        i + 1 > length(all_rows) && continue
        next_row = all_rows[i + 1]

        if label == "Cost"
            # ✖ N text gives research_units
            full_text = node_text(next_row)
            m = match(r"✖\s*(\d+)", full_text)
            m !== nothing && (research_units = parse(Int, m.captures[1]))

            for icon in eachmatch(sel("div.factorio-icon"), next_row)
                link = first_match("a", icon)
                link === nothing && continue
                href       = get(attrs(link), "href", "")
                title_attr = get(attrs(link), "title", wiki_to_id(lstrip(href, '/')))
                icon_name  = wiki_to_id(title_attr)
                amt_el     = first_match("div.factorio-icon-text", icon)
                amount     = amt_el !== nothing ? parse_num(trim_text(amt_el), 1.0) : 1.0

                if href == "/Time" || icon_name == "time"
                    time_per_unit = amount
                else
                    push!(sci_ingredients, icon_name => amount)
                end
            end

        elseif label == "Required technologies"
            for a in eachmatch(sel("a"), next_row)
                t = get(attrs(a), "title", "")
                isempty(t) && continue
                # Strip " (research)" suffix to get the internal tech name
                clean = replace(t, r"\s*\(research\)\s*$" => "")
                push!(prerequisites, wiki_to_id(clean))
            end

        elseif label == "Effects"
            for a in eachmatch(sel("a"), next_row)
                t = get(attrs(a), "title", "")
                isempty(t) || push!(effects, wiki_to_id(t))
            end
        end
    end

    return Dict{String,Any}(
        "name"           => name,
        "display_name"   => page_title,
        "icon_url"       => infobox_icon_url(doc),
        "time_per_unit"  => time_per_unit,
        "research_units" => research_units,
        "ingredients"    => [Dict("name" => n, "amount" => a) for (n, a) in sci_ingredients],
        "prerequisites"  => prerequisites,
        "effects"        => effects,
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
        "icon_url"     => infobox_icon_url(doc),
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

function scrape_planet(title::String, doc::HTMLDocument)::Dict
    name = wiki_to_id(title)

    # Planet pages have two Property/Value wikitables:
    # Table 1 → surface stats; last such table → orbit stats (space platform).
    prop_tables = filter(eachmatch(sel("table.wikitable"), doc.root)) do tbl
        rows = eachmatch(sel("tr"), tbl)
        isempty(rows) && return false
        headers = [strip(node_text(h)) for h in eachmatch(sel("th"), rows[1])]
        "Property" in headers && "Value" in headers
    end

    surface = Dict{String,String}()
    orbit   = Dict{String,String}()

    if length(prop_tables) >= 1
        for row in eachmatch(sel("tr"), prop_tables[1])[2:end]
            cells = eachmatch(sel("td"), row)
            length(cells) >= 2 || continue
            surface[strip(node_text(cells[1]))] = strip(node_text(cells[2]))
        end
    end
    if length(prop_tables) >= 2
        for row in eachmatch(sel("tr"), prop_tables[end])[2:end]
            cells = eachmatch(sel("td"), row)
            length(cells) >= 2 || continue
            orbit[strip(node_text(cells[1]))] = strip(node_text(cells[2]))
        end
    end

    # Planet icon: first image whose src contains the page title (as filename)
    icon_url = nothing
    name_pat = replace(title, " " => "_")
    for img in eachmatch(sel("img"), doc.root)
        src = get(attrs(img), "src", "")
        if occursin(name_pat, src)
            icon_url = normalize_icon_url(src)
            break
        end
    end

    return Dict{String,Any}(
        "name"                => name,
        "display_name"        => title,
        "icon_url"            => icon_url,
        "pollutant_type"      => get(surface, "Pollutant Type",     "None"),
        "day_night_cycle"     => parse_num(get(surface, "Day Night Cycle",  "0"), 0.0),
        "magnetic_field"      => parse_num(get(surface, "Magnetic Field",    "0"), 0.0),
        "solar_power_surface" => parse_num(get(surface, "Solar Power",       "0"), 0.0),
        "pressure"            => parse_num(get(surface, "Pressure",          "0"), 0.0),
        "gravity"             => parse_num(get(surface, "Gravity",           "0"), 0.0),
        "robot_energy_usage"  => parse_num(get(surface, "Robot energy usage","100"), 100.0),
        "solar_power_orbit"   => parse_num(get(orbit,   "Solar Power",       "0"), 0.0),
    )
end

# ── Output helpers ────────────────────────────────────────────────────────────

function recipe_to_dict(r::Recipe, name::String, fallback_icon_url=nothing)::Dict
    Dict{String,Any}(
        "name"          => name,
        "crafting_time" => r.crafting_time,
        "ingredients"   => [Dict("name" => i.name, "type" => i.type, "amount" => i.amount)
                             for i in r.ingredients],
        "products"      => [Dict("name" => p.name, "type" => p.type,
                                 "amount" => p.amount, "probability" => p.probability)
                             for p in r.products],
        "made_in"       => r.made_in,
        # Prefer the process-specific icon; fall back to primary product's icon.
        "icon_url"      => !isempty(r.icon_url) ? r.icon_url : fallback_icon_url,
    )
end

# ── Main ──────────────────────────────────────────────────────────────────────

function main()
    out = Dict{String,Any}(
        "version"      => "2.0",
        "scraped_at"   => string(today()),
        "items"        => Dict{String,Any}(),
        "fluids"       => Dict{String,Any}(),
        "recipes"      => Dict{String,Any}[],   # list — multiple recipes per product allowed
        "machines"     => Dict{String,Any}(),
        "modules"      => Dict{String,Any}(),
        "technologies" => Dict{String,Any}(),
        "planets"      => Dict{String,Any}(),
    )

    # ── Items & fluids (+ their recipes) ──────────────────────────────────────
    # Scrape all major item categories; pages without an "Internal name" infobox
    # field are gameplay-concept pages (not craftable items) and are skipped.
    item_categories = [
        "Intermediate_products",
        "Logistics",
        "Production",
        "Combat",
    ]

    # Pages explicitly handled as machines or modules — don't re-scrape as items.
    known_non_items = Set(vcat(MACHINE_PAGES, MODULE_PAGES))

    seen_titles = Set{String}()   # deduplicate across categories

    for cat in item_categories
        titles = category_members(cat; recurse=true)
        println("── Scraping $cat ($(length(titles)) pages)...")

        for title in titles
            title in seen_titles   && continue
            title in known_non_items && continue
            push!(seen_titles, title)

            @info "  $title"
            doc = try fetch_html(title)
            catch e
                @warn "  skip '$title': $e"
                continue
            end

            # Skip gameplay-concept pages that have no item infobox.
            internal_name = infobox_value(doc, "Internal name")
            internal_name === nothing && continue

            if is_fluid_page(doc)
                fluid = scrape_fluid(title, doc)
                out["fluids"][fluid["name"]] = fluid
            else
                item = scrape_item(title, doc)
                out["items"][item["name"]] = item
            end

            # Use the Process-column name when available; fall back to product name.
            recipes = scrape_recipes(doc)
            for (i, recipe) in enumerate(recipes)
                name = !isempty(recipe.name) ? recipe.name :
                       length(recipe.products) == 1 ? recipe.products[1].name :
                       length(recipe.products) > 1  ? join([p.name for p in recipe.products], "+") :
                       internal_name
                # Avoid duplicate names when a page produces multiple recipe variants
                existing_names = Set(r["name"] for r in out["recipes"])
                name in existing_names && (name = "$(name)-$(i)")
                push!(out["recipes"], recipe_to_dict(recipe, name))
            end
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

    # ── Fill missing recipe icon_url from primary product ────────────────────
    # Wikitable recipes already have their own process icon; only fill the gap
    # for infobox recipes that have no dedicated process image.
    icon_lookup = Dict{String,Union{String,Nothing}}()
    for (name, desc) in merge(out["items"], out["fluids"])
        icon_lookup[name] = get(desc, "icon_url", nothing)
    end
    for recipe in out["recipes"]
        get(recipe, "icon_url", nothing) !== nothing && continue   # already set
        prods = recipe["products"]
        recipe["icon_url"] = isempty(prods) ? nothing : get(icon_lookup, prods[1]["name"], nothing)
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

    # ── Technologies ──────────────────────────────────────────────────────────
    println("── Scraping technologies...")
    tech_titles = category_members("Technology"; recurse=false)
    println("   $(length(tech_titles)) pages in Category:Technology")
    for title in tech_titles
        @info "  $title"
        doc = try fetch_html(title) catch e; @warn "  skip '$title': $e"; continue end
        internal_name = infobox_value(doc, "Internal name")
        internal_name === nothing && continue   # skip concept pages
        t = scrape_technology(title, doc)
        out["technologies"][t["name"]] = t
    end

    # ── Planets ───────────────────────────────────────────────────────────────
    println("── Scraping planets...")
    for title in PLANET_PAGES
        @info "  $title"
        doc = try fetch_html(title) catch e; @warn "  skip '$title': $e"; continue end
        p = scrape_planet(title, doc)
        out["planets"][p["name"]] = p
    end

    # ── Write output ──────────────────────────────────────────────────────────
    output_path = joinpath(@__DIR__, "factorio2_data.json")
    open(output_path, "w") do f
        JSON.print(f, out, 2)
    end

    println("\nDone → $output_path")
    println("  items:        $(length(out["items"]))")
    println("  fluids:       $(length(out["fluids"]))")
    println("  recipes:      $(length(out["recipes"])) ($(length(Set(r["name"] for r in out["recipes"]))) unique names)")
    println("  machines:     $(length(out["machines"]))")
    println("  modules:      $(length(out["modules"]))")
    println("  technologies: $(length(out["technologies"]))")
    println("  planets:      $(length(out["planets"]))")
end

main()
