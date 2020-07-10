# Many query operations involve date intervals. We can't use native
# Julia range object since it's a vector, and vectors are lifted to a
# plural value rather than treated as a tuple. That said, we could
# create a custom type, `TimeInterval`, lifted to combinators. This
# sort of interval is inclusive of endpoints.

DateType = TimeZones.ZonedDateTime

struct TimeInterval
    start_time::DateType
    end_time::DateType
end

Base.show(io::IO, i::TimeInterval) =
    print(io, "$(i.start_time) to $(i.end_time)")

TimeInterval(start_time::String, end_time::String) =
    TimeInterval(DateType(start_time), DateType(end_time))
translate(mod::Module, ::Val{:time_interval}, args::Tuple{Any, Any}) =
    TimeInterval.(translate.(Ref(mod), args)...)

Lift(::Type{TimeInterval}) =
    DispatchByType(TimeInterval => It,
                   DateType => TimeInterval.(It, It),
                   ZonedDateType => TimeInterval(DateType(It), DateType(It)),
                   String => TimeInterval.(DateType.(It), DateType.(It))) >>
    Label(:time_interval)
translate(::Module, ::Val{:time_interval}) = Lift(TimeInterval)

lookup(ity::Type{TimeInterval}, name::Symbol) =
    if name in (:start_time, :end_time)
        lift(getfield, name) |> designate(ity, DateType)
    end

# We define `includes` to mean that a date falls within a date interval
# inclusively, or that one interval is completely subsumed by another.

includes(period::TimeInterval, val::String) =
    includes(period, DateType(val))

includes(period::TimeInterval, val::DateType) =
    period.end_time >= val >= period.start_time

includes(period::TimeInterval, val::TimeInterval) =
   (val.start_time >= period.start_date) &&
   (period.end_time >= val.end_date)

# we define 

and_previous(init::DateType, len::Day) =
    TimeInterval(init - len, init)
and_subsequent(init::DateType, len::Day) =
    TimeInterval(init, init + len)
and_previous(di::TimeInterval, len::Day) =
    TimeInterval(di.start_time - len, di.end_time)
and_subsequent(di::TimeInterval, len::Day) =
    TimeInterval(di.start_time, di.end_time + len)

"""
X >> Includes(Y)
This combinator is true if the interval of `Y` is completely included
in the interval for `X`.  That is, if the starting point of `Y` is
greater than or equal to the starting point of `X`, and also if the
ending point of `Y` is less than or equal to the ending point of `X`.
This combinator accepts a `TimeInterval` for its arguments, but also
any object that has `StartDate` and `EndDate` defined.
"""
Includes(Y) = includes.(It, Y)
translate(mod::Module, ::Val{:includes}, args::Tuple{Any}) =
    Includes(translate.(Ref(mod), args)...)

During(Y) = includes.(Y, It)
translate(mod::Module, ::Val{:during}, args::Tuple{Any}) =
    During(translate.(Ref(mod), args)...)

AndPrevious(Y) = and_previous.(It >> TimeInterval, Lift(Day, (Y,)))
translate(mod::Module, ::Val{:and_previous}, args::Tuple{Any}) =
    AndPrevious(translate.(Ref(mod), args)...)

AndSubsequent(Y) = and_subsequent.(It >> TimeInterval, Lift(Day, (Y,)))
translate(mod::Module, ::Val{:and_subsequent}, args::Tuple{Any}) =
    AndSubsequent(translate.(Ref(mod), args)...)

