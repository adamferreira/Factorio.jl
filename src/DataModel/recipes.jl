"""
    Struct that hold Recipe relation information (i,j):
    - Amount of item i needed in recipe j
    - Or amount of item j produced by recipe i
    - Probability of producing item j by recipe i
"""
struct RecipeGraphEdge
    amount::Float64
    probability::Float64
end

"""
    Struct that hold either Ingredient or Recipe nodes:
    - `id` is an item id if this is a Ingredient node
    - `id` is arecipe id if this is a Recipe node
"""
struct RecipeGraphNode
    id::Int64
end

# Type definition (for easy function definition)
const LabelType = Int64
const CodeType = Int64
const VectexType = RecipeGraphNode
const EdgeType = RecipeGraphEdge


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
    Graphs.SimpleDiGraph(), # indexes types for vertices is Int64 in SimpleDiGraph
    Label = LabelType, # how vertices and edges are identified
    VertexData = VectexType,  # struct that holds vertex metadata, here we work with UniqueElement's uids
    EdgeData  = EdgeType, # struct that holds edge metadata
    graph_data = database(), # struct that holds graph metadata, here we store a pointer to the efault database
    weight_function = edata -> 1.0, # function to attribute weights to edges
    default_weight = 1.0
)