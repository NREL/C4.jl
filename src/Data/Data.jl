module Data

using Dates, DelimitedFiles

import Base: length

# TimePeriod: continguous grouping of timesteps: name and integer range
# [Ecnomic,Adequacy]Dispatch: Spatiotemporal collection of dispatch decisions associated with one or more equal-length TimePeriods - includes RegionDispatches, InterfaceDispatches, any potential adequacy construct
# DispatchRecurrence: Finite repetition of Dispatch actions. Corresponds to a set of sequential TimePeriods. Includes start/end conditions
# DispatchSequence: Chain of DispatchRecurrences with linking constraints between start/end conditions

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
