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
    Label = String, # how vertices and edges are identified
    VertexData = RecipeNode,  # struct that holds vertex metadata
    EdgeData  = RecipeEdge, # struct that holds edge metadata
    graph_data = nothing, # struct that holds graph metadata
    weight_function = edata -> 1.0, # function to attribute weights to edges
    default_weight = 1.0
)

add_recipe_node!(r, n::RecipeNode) = Graphs.add_vertex!(r, n.name, n)
add_recipe_edge!(r, src::String, dst::String, e::RecipeEdge) = Graphs.add_edge!(r, src, dst, e)


# Get all recipes that produces or consume this item
function focus(g, item::String)
    vcode = code_for(g, item)
    vertices = vcat(vcode, Graphs.inneighbors(g, vcode), Graphs.outneighbors(g, vcode))
    subgrah, map = MetaGraphsNext.induced_subgraph(g, vertices)
    return subgrah
end

# Plot overload
function rplot(r)
    function color(n::RecipeNode)
        if n.type == RECIPE return GraphPlot.colorant"orange" end
        if n.type == ITEM return GraphPlot.colorant"lightseagreen" end
        if n.type == RESSOURCE return GraphPlot.colorant"blue" end
    end
    nlabels = ["$(MetaGraphsNext.label_for(r,v))\n$(r[label_for(r,v)].craft_time)" for v in collect(Graphs.vertices(r))]
    ncolors = [color(r[label_for(r,v)]) for v in collect(Graphs.vertices(r))]
    elabels = [r[label_for(r,src(e)), label_for(r,dst(e))].amount for e in collect(Graphs.edges(r))]
    return GraphPlot.gplot(
        r.graph,
        nodelabel = nlabels,
        edgelabel = elabels,
        nodefillc = ncolors,
        arrowlengthfrac = 0.01
    )
end