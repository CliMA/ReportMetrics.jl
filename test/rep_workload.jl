import Profile
x = rand(1000)

function foo()
    s = 0.0
    for i in x
        s += i - rand()
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
