module Data

using Dates, DelimitedFiles

import Base: length

export availability, TimePeriod, TechnologyParams, GeneratorParams,
       ThermalParams, ThermalSiteParams,
       VariableParams, VariableSiteParams,
       StorageParams, StorageSiteParams,
       RegionParams, InterfaceParams, SystemParams

include("time.jl")
include("resources.jl")

include("import_validation.jl")
include("import.jl")

end
