# Many query operations involve date intervals. We can't use native
# Julia range object since it's a vector, and vectors are lifted to a
# plural value rather than treated as a tuple. That said, we could
# create a custom type, `DateInterval`, lifted to combinators. This
# sort of interval is inclusive of endpoints.

struct DateInterval
    start_date::Date
    end_date::Date
end
Base.show(io::IO, i::DateInterval) =
    print(io, "$(i.start_date) to $(i.end_date)")

DateInterval(start_date::String, end_date::String) =
    DateInterval(Date(start_date), Date(end_date))
translate(mod::Module, ::Val{:date_interval}, args::Tuple{Any, Any}) =
    DateInterval.(translate.(Ref(mod), args)...)

Lift(::Type{DateInterval}) =
    DispatchByType(DateInterval => It,
                   Date => DateInterval.(It, It),
                   String => DateInterval.(Date.(It), Date.(It)),
                   Any => DateInterval.(StartDate, EndDate)) >>
    Label(:date_interval)
translate(::Module, ::Val{:date_interval}) = Lift(DateInterval)

lookup(ity::Type{DateInterval}, name::Symbol) =
    if name in (:start_date, :end_date)
        lift(getfield, name) |> designate(ity, Date)
    end

# We define `includes` to mean that a date falls within a date interval
# inclusively, or that one interval is completely subsumed by another.

includes(period::DateInterval, val::String) =
    includes(period, Date(val))

includes(period::DateInterval, val::Date) =
    period.end_date >= val >= period.start_date

includes(period::DateInterval, val::DateInterval) =
   (val.start_date >= period.start_date) &&
   (period.end_date >= val.end_date)

# we define 

and_previous(init::Date, len::Day) =
    DateInterval(init - len, init)
and_subsequent(init::Date, len::Day) =
    DateInterval(init, init + len)
and_previous(di::DateInterval, len::Day) =
    DateInterval(di.start_date - len, di.end_date)
and_subsequent(di::DateInterval, len::Day) =
    DateInterval(di.start_date, di.end_date + len)

"""
    collapse_intervals(intervals, allowance)
This function collapses a vector of intervals based upon an
allowance, such as 180days between the end of a previous interval,
and the start of the next.
"""
function collapse_intervals(intervals::Vector{DateInterval},
                            allowance::Day)
    intervals′ = Vector{DateInterval}()
    c = nothing
    for i in sort(intervals, by=(i -> i.start_date))
        if c === nothing
            c = i
        elseif c.end_date + allowance < i.start_date
            push!(intervals′, c)
            c = i
        elseif c.end_date < i.end_date
            c = DateInterval(c.start_date, i.end_date)
        end
    end
    if c !== nothing
        push!(intervals′, c)
    end
    intervals′
end

CollapseIntervals(A, I) = collapse_intervals.(I >> DateInterval, A)
ReverseCollapse(I, A) = CollapseIntervals(A, I)
CollapseIntervals(A) = DataKnots.Then(ReverseCollapse, (A,))

translate(mod::Module, ::Val{:collapse_intervals},
          args::Tuple{Any, Any}) =
    CollapseIntervals(translate.(Ref(mod), args)...)

translate(mod::Module, ::Val{:collapse_intervals},
          args::Tuple{Any}) =
    CollapseIntervals(translate.(Ref(mod), args)...)

"""
X >> Includes(Y)
This combinator is true if the interval of `Y` is completely included
in the interval for `X`.  That is, if the starting point of `Y` is
greater than or equal to the starting point of `X`, and also if the
ending point of `Y` is less than or equal to the ending point of `X`.
This combinator accepts a `DateInterval` for its arguments, but also
any object that has `StartDate` and `EndDate` defined.
"""
Includes(Y) = includes.(It >> DateInterval, Y >> DateInterval)
translate(mod::Module, ::Val{:includes}, args::Tuple{Any}) =
    Includes(translate.(Ref(mod), args)...)

During(Y) = includes.(Y >> DateInterval, It >> DateInterval)
translate(mod::Module, ::Val{:during}, args::Tuple{Any}) =
    During(translate.(Ref(mod), args)...)

AndPrevious(Y) = and_previous.(It >> DateInterval, Lift(Day, (Y,)))
translate(mod::Module, ::Val{:and_previous}, args::Tuple{Any}) =
    AndPrevious(translate.(Ref(mod), args)...)

AndSubsequent(Y) = and_subsequent.(It >> DateInterval, Lift(Day, (Y,)))
translate(mod::Module, ::Val{:and_subsequent}, args::Tuple{Any}) =
    AndSubsequent(translate.(Ref(mod), args)...)

