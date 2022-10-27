using Factorio

m = DefaultFactorioDataBase()
a = AssemblingMachine(3, m)

function test()
    @show sizeof(m)
    @show typeof(a)
    @show sizeof(a)
    @show consumption(Electricity, a)
    @show consumption(Fuel, a)
    @show tier(a)
    @show typeof(a)
end
#@show consumption.(Electricity, [a,a,a])
load_default()