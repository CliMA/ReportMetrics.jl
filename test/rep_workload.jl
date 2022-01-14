import Profile


x = rand(10000)

function foo()
    s = 0.0
    for i in x
        s += i
    end
    return s
end

for i in 1:1000
    foo()
end
Profile.clear_malloc_data()
for i in 1:1000
    foo()
end
