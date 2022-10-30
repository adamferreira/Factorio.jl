using Factorio
using GraphPlot, Compose
using Graphs, MetaGraphsNext

function test()
    @show sizeof(m)
    @show typeof(a)
    @show sizeof(a)
    @show consumption(Electricity, a)
    @show consumption(Fuel, a)
    @show tier(a)
    @show typeof(a)
end

g = database().recgraph
@show typeof(g)
@show typeof(g.graph)

f = Factorio.focus(g, "recipe-low-density-structure")
@show [1:Graphs.ne(f)]
Compose.draw(SVG("factorio.svg", 100cm, 100cm), Factorio.rplot(f))

ironplate = code_for(g,"iron-plate")