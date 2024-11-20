abstract type Site end

"""
StorageSite is an abstract type that can be used to instantiate
dispatch problems. Instances of StorageSite should define:
```
maxpower(::StorageSite)
maxenergy(::StorageSite)
```
"""
abstract type StorageSite <: Site end
abstract type GeneratorSite <: Site end
abstract type ThermalSite <: Site end
abstract type VariableSite <: Site end

abstract type Technology end

"""
GeneratorTechnology is an abstract type that can be used to instantiate
dispatch problems. Instances of GeneratorTechnology should define:
```
cost_generation(::GeneratorTechnology)
capacity_available(::GeneratorTechnology)
capacity_nameplate(::GeneratorTechnology)
```
"""
abstract type GeneratorTechnology <: Technology end
function cost_generation end
function availablecapacity end

"""
StorageTechnology is an abstract type that can be used to instantiate
dispatch problems. Instances of StorageTechnology should define:
```
rating_power(::StorageTechnology)
rating_energy(::StorageTechnology)
```
"""
abstract type StorageTechnology{SS<:StorageSite} <: Technology end
function maxenergy end
function maxpower end
function operating_cost end
function roundtrip_efficiency end

abstract type ThermalTechnology <: GeneratorTechnology end
abstract type VariableTechnology <: GeneratorTechnology end

abstract type Interface end
function region_from end
function region_to end

"""
Region is an abstract type that can be used to instantiate
dispatch problems. Instances of Region should define:
```
name(::Region)
demand(::Region, t::Int)
```
"""
abstract type Region{
    TG<:ThermalTechnology, VG<:VariableTechnology,
    ST<:StorageTechnology, SS<:StorageSite, I<:Interface}
end
function name end
function demand end
function importinginterfaces end
function exportinginterfaces end

function cost end

function solve! end

function store end

abstract type System{R<:Region, I<:Interface} end
