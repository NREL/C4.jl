module Data

using Dates, DelimitedFiles

import Base: length

import ..ThermalSite, ..VariableSite, ..StorageSite, ..Technology,
       ..ThermalTechnology, ..VariableTechnology, ..StorageTechnology,
       ..Interface, ..Region, ..System, ..cost_generation,
       ..maxpower, ..maxenergy, ..availablecapacity, ..region_from, ..region_to,
       ..demand, ..importinginterfaces, ..exportinginterfaces, ..name

# TODO: Rename Period -> DispatchPeriod and TimePeriod -> Period
export availability, TimePeriod, Period, TimeProxyAssignment,
       GeneratorParams, GeneratorSiteParams,
       ThermalParams, ThermalSiteParams,
       VariableParams, VariableSiteParams,
       StorageParams, StorageSiteParams,
       RegionParams, InterfaceParams, SystemParams,
       timestepcount,
       singleperiod, seasonalperiods, monthlyperiods,
       weeklyperiods, dailyperiods, fullchronologyperiods,
       store_adequacy_iteration, store_optimization_iteration,
       store_full_iteration

include("time.jl")
include("sites.jl")
include("technologies.jl")
include("system.jl")

include("representative_periods.jl")

include("import_validation.jl")
include("import.jl")
include("export.jl")

end
