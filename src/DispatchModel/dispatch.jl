# TODO: Differentiate reliability vs economic dispatch in variable names

"""
GeneratorDispatch contains optimization problem components for
dispatching a GeneratorTechnology. GeneratorDispatch constructors should take
the following arguments:
```
GeneratorDispatch(::JuMP.Model, ::Region, GeneratorTechnology, ::TimePeriod)
```
"""
struct GeneratorDispatch{G<:GeneratorTechnology}

    dispatch::Vector{JuMP.VariableRef}
    dispatch_max::Vector{JuMP_LessThanConstraintRef}

    gen::G

end

cost(dispatch::GeneratorDispatch) =
    sum(dispatch.dispatch) * cost_generation(dispatch.gen)

struct StorageSiteDispatch{S<:StorageSite}

    dispatch::Vector{JuMP.VariableRef}

    dispatch_min::Vector{JuMP_LessThanConstraintRef}
    dispatch_max::Vector{JuMP_LessThanConstraintRef}

    e_net::JuMP_ExpressionRef # MWh

    e_high::JuMP.VariableRef # MWh
    e_high_def::Vector{JuMP_LessThanConstraintRef}

    e_low::JuMP.VariableRef # MWh
    e_low_def::Vector{JuMP_LessThanConstraintRef}

    site::S

end

"""
StorageDispatch contains optimization problem components for
dispatching a StorageTechnology. StorageDispatch constructors should take
the following arguments:
```
StorageDispatch(::JuMP.Model, ::Region, ::StorageTechnology, ::TimePeriod)
```
"""
struct StorageDispatch{ST<:StorageTechnology, SS<:StorageSite}

    sites::Vector{StorageSiteDispatch{SS}}

    dispatch::Vector{JuMP_ExpressionRef}

    stor::ST

end

"""
InterfaceDispatch contains optimization problem components for
dispatching an Interface. InterfaceDispatch constructors should take
the following arguments:
```
InterfaceDispatch(::JuMP.Model, ::Interface, ::TimePeriod)
```
"""
struct InterfaceDispatch{I<:Interface}

    flow::Vector{JuMP.VariableRef}

    flow_min::Vector{JuMP_GreaterThanConstraintRef}
    flow_max::Vector{JuMP_LessThanConstraintRef}

    iface::I

end

"""
RegionDispatch is an abstract type for holding optimization problem components
for dispatching a Region. RegionDispatch instance constructors should take the
following arguments:
```
RegionDispatch(::JuMP.Model, ::Region, ::Vector{InterfaceDispatch}, ::TimePeriod)
```
"""
abstract type RegionDispatch{R<:Region} end

# Do we even need this one?
"""
SystemDispatch contains optimization problem components for
dispatching a System. SystemDispatch constructors should take the
following arguments:
```
SystemDispatch(::JuMP.Model, ::System, ::TimePeriod)
```
"""
abstract type SystemDispatch{S<:System} end
