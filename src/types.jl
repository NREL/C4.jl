abstract type Site end
abstract type Technology end

"""
`VariableSite` is an abstract type that can be used to instantiate dispatch
problems. Instances of `VariableSite` should define:

`nameplatecapacity(site::VariableSite)`
Returns installed capacity in `C4.powerunits_MW`.

`availability(site::VariableSite, t::Int) -> Float64`
Returns a unitless value between 0.0 and 1.0 corresponding to
global timestep `t`.
"""
abstract type VariableSite <: Site end

function availability end
function nameplatecapacity end

availablecapacity(site::VariableSite, t::Int) =
    nameplatecapacity(site) * availability(site, t)


"""
`VariableTechnology` is an abstract type that can be used to instantiate
dispatch problems. Instances of `VariableTechnology` should define:

`name(tech::VariableTechnology) -> AbstractString`
Returns the technology name.

`sites(tech::VariableTechnology) -> Vector{<:VariableSite}`
Returns a vector of the `VariableSite`s associated with the `VariableTechnology`.

`cost_generation(tech::VariableTechnology) -> Float64`
Returns the marginal generating cost of `tech` in units of \$/C4.powerunits_MW.
"""
abstract type VariableTechnology <: Technology end

function name end
function sites end
function cost_generation end

nameplatecapacity(tech::VariableTechnology) =
    sum(nameplatecapacity(site) for site in sites(tech); init=0)

availablecapacity(tech::VariableTechnology, t::Int) =
    sum(availablecapacity(site, t) for site in sites(tech); init=0)


abstract type ThermalSite <: Site end
abstract type ThermalTechnology <: Technology end

"""
StorageTechnology is an abstract type that can be used to instantiate
dispatch problems. Instances of StorageTechnology should define:

```
maxpower(::StorageTechnology)
maxenergy(::StorageTechnology)
operating_cost(::StorageTechnology) -> Float64
roundtrip_efficiency(::StorageTechnology) -> Float64
```
"""
abstract type StorageTechnology <: Technology end

function maxenergy end
function maxpower end
function operating_cost end
function roundtrip_efficiency end

abstract type Interface end
function region_from end
function region_to end

"""
Region is an abstract type that can be used to instantiate
dispatch problems. Instances of Region should define:
```
name(::Region)
demand(::Region, t::Int)
variabletechs(::Region) -> Vector{VariableTechnology}
storagetechs(::Region) -> Vector{StorageTechnology}
```
"""
abstract type Region{TG<:ThermalTechnology, I<:Interface} end

function demand end
function variabletechs end
function storagetechs end
function importinginterfaces end
function exportinginterfaces end

function cost end

function solve! end

function store end

abstract type System{R<:Region, I<:Interface} end
