using Factorio

m = DefaultFactorioDataBase()
a = AssemblingMachine(3, m)
@show typeof(a)
@show sizeof(a)
@show consumption(Electricity, a)
@show consumption(Fuel, a)
@show tier(a)
@show typeof(a)