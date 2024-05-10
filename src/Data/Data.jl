module Data

using Dates, DelimitedFiles

import Base: length

export availability, TimePeriod, Region, ResourceTechnology,
       ThermalTechnology, ThermalSite, VariableTechnology, VariableSite,
       GeneratorTechnology, StorageTechnology, StorageSite, Interface, System

include("time.jl")
include("resources.jl")

include("import_validation.jl")
include("import.jl")

end
