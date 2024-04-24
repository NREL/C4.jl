struct TimePeriod
    timesteps::UnitRange{Int}
    name::String
end

length(t::TimePeriod) = length(t.timesteps)
