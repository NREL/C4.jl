import C4.ExpansionModel: deduplicate

@test deduplicate(Int[]) == Pair{Int,Int}[]
@test deduplicate(ones(Int,5)) == [1=>5]
@test deduplicate(collect(1:10)) == map(x -> x=>1, 1:10)
@test deduplicate([1,1,2,3,2,2,3]) == [1=>2, 2=>1, 3=>1, 2=>2, 3=>1]
