abstract type Dispatch end

struct EconomicDispatch <: Dispatch

end

struct ReliabilityDispatch <: Dispatch

end

struct DispatchRecurrence{D <: Dispatch}

    dispatch::D
    repetitions::Int

    next_recurrence::Union{DispatchRecurrence{D}, Nothing}

end

mutable struct DispatchSequence{D <: Dispatch}

    dispatches::Vector{D}

    first_recurrence::Union{DispatchRecurrence{D}, Nothing}

    function DispatchSequence{D}(sys::System, time::TimeProxyAssignment) where D
        new(D[], nothing)
    end

end

