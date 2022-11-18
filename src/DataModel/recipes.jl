"""
    Struct that hold Recipe relation information:
    - Amount of item i needed in recipe j
    - Or amount of item i produced by recipe j
"""
struct RecipeEdge
    amount::Float64
    probability::Float64
end

# Type definition (for easy function definition)
const LabelType = UniqueID
const CodeType = Int64
const VectexType = AbstractDataModel
const EdgeType = RecipeEdge

#for f in [:Δin, :Δout]
#    @eval $f(meta_graph::MetaGraph) = Graphs.$f(meta_graph.graph)
#end
"""
struct MetaGraph{
    Code <: Integer,
    Label,
    Graph,
    VertexData,
    EdgeData,
    GraphData,
    WeightFunction,
    Weight <: Real,
} <: AbstractGraph{Code}
RecipeGraph = MetaGraphsNext.MetaDiGraph{
    Int64, # idexes types for vertices
    String, # how vertices and edges are identified
    MetaGraphsNext.SimpleDiGraph, # graph type
    Symbol, # struct that holds vertex metadata
    Symbol, # struct that holds edge metadata
    String, # struct that holds graph metadata
    edata -> 1.0, # function to attribute weights to edges
    Float64, # Weight type for edges
}

A recipe graph have 3 different types of UniqueElement as nodes:
- Resources, that may be roots of the recipe graph (some recipes creates water for example)
- Recipes, they allways have in and out neighbors
- Items, produced by recipes, some used by recipes, may be leaves of the RecipeGraph
"""
RecipeGraph() = MetaGraphsNext.MetaGraph(
    Graphs.SimpleDiGraph(), # idexes types for vertices is Int64 in SimpleDiGraph
    Label = LabelType, # how vertices and edges are identified
    VertexData = VectexType,  # struct that holds vertex metadata, here we work with UniqueElement's uids
    EdgeData  = EdgeType, # struct that holds edge metadata
    graph_data = Dict{String, LabelType}, # struct that holds graph metadata, here we store names to uid mapping
    weight_function = edata -> 1.0, # function to attribute weights to edges
    default_weight = 1.0
)

add_recipe_node!(r, n::VectexType) = Graphs.add_vertex!(r, n.name, n)
add_recipe_edge!(r, src::LabelType, dst::LabelType, e::EdgeType) = Graphs.add_edge!(r, src, dst, e)

"""
    Returns the labels of `vertices` codes
"""
labels(g, codes::AbstractVector{CodeType}) = [MetaGraphsNext.label_for(g,v) for v in codes]
labels(codes) = labels(recipes(), codes)

"""
    Returns the cdes of `vertices` from labels
"""
codes(g, labels::AbstractVector{LabelType}) = [MetaGraphsNext.code_for(g,v) for v in labels]
codes(labels) = labels(recipes(), labels)
code(label) = codes([label])

"""
    Overrides,
    Return the (non-repetitive) list of vertices that are the inneighbors of `v`
"""
function Graphs.inneighbors(g, vertices::AbstractVector{CodeType})
    f = v -> Graphs.inneighbors(g, v)
    neighbors = vcat(collect(Iterators.map(f, vertices))...)
    # Setify vertices to have unique occurences
    return collect(Set(neighbors))
end

"""
    Overrides,
    Return the (non-repetitive) list of vertices that are the outneighbors of `v`
"""
function Graphs.outneighbors(g, vertices::AbstractVector{CodeType})
    f = v -> Graphs.outneighbors(g, v)
    neighbors = vcat(collect(Iterators.map(f, vertices))...)
    # Setify vertices to have unique occurences
    return collect(Set(neighbors))
end

function __dfs(g, vertices::AbstractVector{CodeType}, neighborhood_f)
    s = Vector{CodeType}()
    all_a = Set{CodeType}()
    push!(s, vertices...)
    while length(s) > 0
        a = pop!(s)
        if a ∉ all_a
            push!(s, neighborhood_f(g,a)...)
            push!(all_a, a)
        end
    end
    return collect(all_a)
end

"""
    Get `vertices` and theyre ancestors (unique occurence) in `g`.
"""
parents(g, vertices::AbstractVector{CodeType}) = __dfs(g, vertices, Graphs.inneighbors)
"""
    Get `vertices` and theyre offsprings (unique occurence) in `g`.
"""
children(g, vertices::AbstractVector{CodeType}) = __dfs(g, vertices, Graphs.outneighbors)

function related_graph(g, items::AbstractVector{CodeType})
    # Get the induced_subgraph from all nodes related to `items`
    subgrah, map = MetaGraphsNext.induced_subgraph(g, items)
    return subgrah
end
# Default redirection, usefull for |> usage
related_graph(items::AbstractVector{CodeType}) = related_graph(recipes(), items)


"""
    Returns all products of nodes `vertices` (i.e. outneighbors)
"""
products(g, vertices::AbstractVector{CodeType}) = Graphs.outneighbors(g, vertices)

"""
    Returns all ingredients of `vertices` (i.e. outneighbors)
"""
ingredients(g, vertices::AbstractVector{CodeType}) = Graphs.inneighbors(g, vertices)

"""
    Returns `items` and all recipes that produces or consumes it
"""
function with_neighbors(g, items::AbstractVector{CodeType})
    vertices = vcat(items, ingredients(g, items), products(g, items))
    return collect(Set(vertices))
end

"""
    Returns `items` and all recipes that produces it
"""
function with_ingredients(g, items::AbstractVector{CodeType})
    vertices = vcat(items, ingredients(g, items))
    return collect(Set(vertices))
end

"""
    Returns `items` and all recipes that consumes it
"""
function with_products(g, items::AbstractVector{CodeType})
    vertices = vcat(items, products(g, items))
    return collect(Set(vertices))
end

"""
    Get all recipes in the graph `g` that have at least one ingredient in `items`
"""
consumes_any(g, items::AbstractVector{CodeType}) = products(g, items) # products of items are recipes in the recipe graph !
"""
    Get all recipes in the graph `g` that have at least all ingredients in `items`
"""
function consumes_all(g, items::AbstractVector{CodeType})
    # Get all different recipes that have (at least) `items` as ingredients (may have others as well)
    # products of items are recipes in the recipe graph !
    recipes = products(g, items)
    # Select only recipes that have `items` in their ingredients list
    return [v for v in recipes if Set(items) ⊆ Set(Graphs.inneighbors(g,v))]
end
"""
    Get all recipes in the graph `g` that have `items` as ingredients
"""
function consumes_only(g, items::AbstractVector{CodeType})
    # Get all different recipes that have (at least) `items` as ingredients (may have others as well)
    # products of items are recipes in the recipe graph !
    recipes = products(g, items)
    # Select only recipes that are connected to item in `items`
    return [v for v in recipes if Set(Graphs.inneighbors(g,v)) == Set(items)]
end

# Internally, all function are meant to be called with nodes identified with their code (index in the graph)
# For performance.
# For convenience, here we specialize each function with labels as identifiers
for f in [
    :products,
    :ingredients,
    :with_neighbors,
    :with_products,
    :with_ingredients,
    :consumes_any,
    :consumes_all,
    :consumes_only,
    :sub_recipe,
    :parents,
    :children
]
    @eval $f(g, x::AbstractVector{LabelType}) = $f(g, [MetaGraphsNext.code_for(g,i) for i in x])
    # Some for variadic argument
    @eval $f(g, x::LabelType...) = $f(g, [MetaGraphsNext.code_for(g,i) for i in x])
    # Define default RecipeGraph call (varags and list)
    @eval $f(x::LabelType...) = $f(recipes(), x...)
    @eval $f(x::AbstractVector{CodeType}) = $f(recipes(), x)
    
    # Define macro call
    #Meta.parse("macro $f(x...) $f(recipes(), x...) end")
end

"""
    Computes the tier of every node on the graph
    A node with no parent (ressource) if of tier zero
    The tier of a node the the maximum of the tiers of its parents + 1
"""
function tiers(g)
    return nothing
end

# Plot overload
function rplot(r)

    function color(n::RecipeNode)
        if n.type == RECIPE return GraphPlot.colorant"orange" end
        if n.type == ITEM return GraphPlot.colorant"lightseagreen" end
        if n.type == RESSOURCE return GraphPlot.colorant"lightblue" end
    end

    function display(n::RecipeNode)
        return n.craft_time == 0.0 ? "$(n.name)" : "$(n.name)\n$(n.craft_time)"
    end

    nlabels = [display(r[MetaGraphsNext.label_for(r,v)]) for v in collect(Graphs.vertices(r))]
    ncolors = [color(r[label_for(r,v)]) for v in collect(Graphs.vertices(r))]
    elabels = [r[label_for(r,src(e)), label_for(r,dst(e))].amount for e in collect(Graphs.edges(r))]
    return GraphPlot.gplot(
        r.graph,
        nodelabel = nlabels,
        edgelabel = elabels,
        nodefillc = ncolors,
        arrowlengthfrac = 0.01,
        edgelabelsize = 100.0,
        nodelabelsize = 4
    )
end