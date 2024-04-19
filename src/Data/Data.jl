module Data

using Dates, DelimitedFiles

import Base: length

export Region, ThermalTechnology, ThermalSite, VariableTechnology, VariableSite,
       StorageTechnology, StorageSite, Interface, System

include("resources.jl")

include("import_validation.jl")
include("import.jl")

end
