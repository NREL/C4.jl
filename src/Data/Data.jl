module Data

using Dates, DelimitedFiles

import Base: length

import ..ThermalSite, ..VariableSite, ..StorageSite, ..Technology,
       ..ThermalTechnology, ..VariableTechnology, ..StorageTechnology,
       ..Interface, ..Region, ..System, ..cost_generation,
       ..maxpower, ..maxenergy, ..roundtrip_efficiency, ..operating_cost,
       ..name, ..variabletechs, ..sites,
       ..availability, ..nameplatecapacity, ..availablecapacity,
       ..region_from, ..region_to,
       ..demand, ..importinginterfaces, ..exportinginterfaces,
       ..powerunits_MW

# TODO: Rename Period -> DispatchPeriod and TimePeriod -> Period
export TimePeriod, Period, TimeProxyAssignment,
       ThermalParams, ThermalSiteParams,
       VariableExistingParams, VariableExistingSiteParams,
       VariableCandidateParams, VariableCandidateSiteParams,
       StorageParams, StorageSiteParams,
       RegionParams, InterfaceParams, SystemParams,
       timestepcount, total_demand,
       singleperiod,
       seasonalperiods, monthlyperiods, weeklyperiods,
       seasonalperiods_byyear, monthlyperiods_byyear, weeklyperiods_byyear,
       dailyperiods, fullchronologyperiods,
       store_iteration, store_iteration_step

include("time.jl")

include("variable.jl")

include("sites.jl")
include("technologies.jl")

include("system.jl")

include("representative_periods.jl")

include("import_validation.jl")
include("import.jl")
include("export.jl")

end
