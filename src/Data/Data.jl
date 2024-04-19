module Data

using Dates, DelimitedFiles

import Base: length

export GenerationTechnology, Generator, GeneratorBuild, GeneratorDispatch,
       StorageTechnology, Storage, StorageBuild, StorageDispatch,
       Region, RegionDispatch,
       Interface, InterfaceBuild, InterfaceDispatch,
       Dispatch, DispatchRecurrence,
       EconomicDispatchSequence, AdequacyDispatchSequence, System,
       subset, make_periods, make_dayperiods, make_partitions, getdays,
       daytohours, season, month, week, season_daytype, month_daytype, week_daytype

include("resources.jl")

include("import_validation.jl")
include("import.jl")

end
