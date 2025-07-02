using LinearAlgebra

const geq0 = >=(0)

"""
Randomly generate an arbitary positive, non-decreasing, concave
N-dimensional function, and use it to populate an N-D array
"""
function cc_data(maxval::Float64, dims::Int...)

    N = length(dims)
    A = rand(N,N)
    A .= (A' .+ A) ./ 2 + 2*I(N) # A is positive and positive semidefinite

    @assert all(geq0, A)
    @assert all(geq0, eigvals(A))

    result = Array{Float64,N}(undef, dims)

    for I in CartesianIndices(result)
        v = collect(dims .- Tuple(I))
        result[I] = v' * A * v
    end

    @assert maximum(result) == first(result)

    result .-= first(result)
    result ./= minimum(result) / maxval

    return result

end

for i in 1:100
    x = cc_data(100., rand(1:10), rand(1:10), rand(1:10), rand(1:10))
    Data.test_valid_ccs(x)
end
