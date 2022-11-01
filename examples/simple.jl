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

g = Factorio.recipes()
@show typeof(g)
@show typeof(g.graph)
@show nv(g)
@show ne(g)

f = Factorio.focus(g, "iron-gear-wheel", "iron-plate", "electronic-circuit")
Compose.draw(SVG("factorio.svg", 100cm, 100cm), Factorio.rplot(f))
#Graphs.savegraph("factorio.dot", f, MetaGraphsNext.DOTFormat())
#Graphs.simplecycles(g)
