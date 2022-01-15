import Profile
import SpecialFunctions

# We're overloading `SpecialFunctions.erf` in this
# absurd way to force allocations in SpecialFunctions
# so to make the report more interesting looking
function SpecialFunctions.erf(x::Float64, y::Float64)
    a = rand(3,3)
    return a[1]
end
x = rand(1000)

function foo()
    s = 0.0
    for i in x
        s += i - SpecialFunctions.erf(rand(), rand())
    end
    return s
end

for i in 1:100
    foo()
end
Profile.clear_malloc_data()
for i in 1:100
    foo()
end
