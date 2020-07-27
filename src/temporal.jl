# Many query operations involve date intervals. We use Julia's
# ``IntervalSets`` library to implement these. Unfortunately,
# it doesn't have a DWIM content-aware parsing library.

function make_interval(s::String)
    @assert length(s) > 2
    @assert s[1] in ('(', '[')
    @assert s[end] in (')', ']')
    @assert contains(s, "..")
    lin = s[1] == '(' ? :open : :closed
    rin = s[end] == ')' ? :open : :closed
    (lhs, rhs) = [strip(z) for z in split(s[2:end-1], "..")]
    if 'T' in lhs
        @assert 'T' in rhs
        lhs = parse(DateTime, lhs)
        rhs = parse(DateTime, rhs)
    elseif '-' in lhs
        @assert '-' in rhs
        lhs = parse(Date, lhs)
        rhs = parse(Date, rhs)
    elseif '.' in lhs
        @assert '.' in rhs
        lhs = parse(Float64, lhs)
        rhs = parse(Float64, rhs)
    else
        lhs = parse(Int64, lhs)
        rhs = parse(Int64, rhs)
    end
    return Interval{lin,rin}(lhs, rhs)
end

translate(mod::Module, ::Val{:interval}, args::Tuple{Any,Vararg{Any}}) =
    make_interval(args...)

# At this time DataKnots does not automatically treat structs
# as fields where lookups happen.

lookup(ity::Type{Interval{L,R,T}}, name::Symbol) where {L,R,T} =
    if name in (:right, :left)
        lift(getfield, name) |> designate(ity, T)
    elseif name in (:start, :begin)
        lift(getfield, :left) |> designate(ity, T)
    elseif name in (:finish, :end)
        lift(getfield, :right) |> designate(ity, T)
    end

# To know if one time interval is within another, we use `issubset`
# passing it the current context to implement includes and during.

Includes(Y) = issubset.(Y, It)
translate(mod::Module, ::Val{:includes}, args::Tuple{Any}) =
    Includes(translate.(Ref(mod), args)...)

During(Y) = issubset.(It, Y)
translate(mod::Module, ::Val{:during}, args::Tuple{Any}) =
    During(translate.(Ref(mod), args)...)

# In macros, which wish to write things like `90days`. For Julia
# this interpreted as "90 * days", hence we just need to make "days"
# be a constant of 1 day.

translate(::Module, ::Val{:days}) = Dates.Day(1)
translate(::Module, ::Val{:years}) = Dates.Year(1)
translate(::Module, ::Val{:months}) = Dates.Month(1)

# Sometimes we want to extend an interval on the right or
# the left.

and_subsequent(it::Interval{L,R,T}, val::Any) where {L,R,T} =
    Interval{L,R,T}(it.left, it.right + val)
AndSubsequent(X) = and_subsequent.(It, X)
translate(mod::Module, ::Val{:and_subsequent}, args::Tuple{Any}) =
    AndSubsequent(translate.(Ref(mod), args)...)

and_previous(it::Interval{L,R,T}, val::Any) where {L,R,T} =
    Interval{L,R,T}(it.left - val, it.right)
AndPrevious(X) = and_previous.(It, X)
translate(mod::Module, ::Val{:and_previous}, args::Tuple{Any}) =
    AndPrevious(translate.(Ref(mod), args)...)
