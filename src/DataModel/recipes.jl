struct RecipeEdge
    amount::Float64
    probability::Float64
end

@enum RecipeType RESSOURCE ITEM RECIPE
struct RecipeNode
    # A recipe can be a resource, an item, or a complex recipe
    name::String
    # Time required to construct the recipe
    craft_time::Float64
    # Time of recipe (ressource, crafted item, recipe node)
    type::RecipeType
end

# Type definition (for easy function definition)
const LabelType = String
const CodeType = Int64
const VectexType = RecipeNode
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
"""
RecipeGraph() = MetaGraphsNext.MetaGraph(
    Graphs.SimpleDiGraph(), # idexes types for vertices is Int64 in SimpleDiGraph
    Label = LabelType, # how vertices and edges are identified
    VertexData = VectexType,  # struct that holds vertex metadata
    EdgeData  = EdgeType, # struct that holds edge metadata
    graph_data = nothing, # struct that holds graph metadata
    weight_function = edata -> 1.0, # function to attribute weights to edges
    default_weight = 1.0
)

add_recipe_node!(r, n::RecipeNode) = Graphs.add_vertex!(r, n.name, n)
add_recipe_edge!(r, src::LabelType, dst::LabelType, e::RecipeEdge) = Graphs.add_edge!(r, src, dst, e)




"""
    Get all recipes that produces or consumes given items.
    The output graph only contains recipe node along with the node associted by the items in argument.
    Returns a RecipeGraph.
"""
function focus(g, items::AbstractVector{CodeType})
    f = v -> vcat(v, Graphs.inneighbors(g, v), Graphs.outneighbors(g, v)) # g is captured
    vertices = vcat(collect(Iterators.map(f, items))...)
    # Setify vertices to have unique occurences
    subgrah, map = MetaGraphsNext.induced_subgraph(g, collect(Set(vertices)))
    return subgrah
end

"""
    Get all recipes in the graph `g` that have at least one ingredient in `items`
"""
function consumes_any(g, items::AbstractVector{CodeType})
    return focus(g, items)
end


# Internally, all function are meant to be called with nodes identified with their code (index)
# For performance.
# For convenience, here we specialize each function with labels as identifiers
for f in [:focus, :consumes_any]
    @eval $f(g, x::AbstractVector{LabelType}) = $f(g, [MetaGraphsNext.code_for(g,i) for i in x])
    # Some for variadic argument
    @eval $f(g, x::LabelType...) = $f(g, [MetaGraphsNext.code_for(g,i) for i in x])
    # Define macro called
    #Meta.parse("macro $f(x...) $f(recipes(), x...) end")
end

"""
    Computes the tier of every node on the graph
    A node with no parent (ressource) if of tier zero
    The tier of a node the the maximum of the tiers of its parents + 1
"""
function tiers(g)
    tiers = Dict()
    # Get ressources nodes
    to_visit = [v for v in Graphs.vertices(g) if Graphs.indegree(g,v) == 0]
    tiers[0] = copy(to_visit)
    @show tiers[0]
    for i in 1:10
        tiers[i] = Set(vcat([Graphs.outneighbors(g,v) for v in tiers[i-1]]...))
        @show tiers[i]
    end
    return tiers
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
        edgelabelsize = 100.0
    )
end