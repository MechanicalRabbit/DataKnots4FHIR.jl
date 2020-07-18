# Many query operations involve date intervals. We can't use native
# Julia range object since it's a vector, and vectors are lifted to a
# plural value rather than treated as a tuple. That said, we could
# create a custom type, `DateTimePeriod`, lifted to combinators. This
# sort of interval is inclusive of stoppoints.

struct DateTimePeriod
    start_time::DateTime
    stop_time::DateTime
end

Base.show(io::IO, i::DateTimePeriod) =
    print(io, "$(i.start_time) to $(i.stop_time)")

DateTimePeriod(start_time::String, stop_time::String) =
    DateTimePeriod(DateTime(start_time), DateTime(stop_time))
translate(mod::Module, ::Val{:period}, args::Tuple{Any, Any}) =
    DateTimePeriod.(translate.(Ref(mod), args)...)

Lift(::Type{DateTimePeriod}) =
    DispatchByType(DateTimePeriod => It,
                   DateTime => DateTimePeriod.(It, It),
                   String => DateTimePeriod.(DateTime.(It), DateTime.(It))) >>
    Label(:period)
translate(::Module, ::Val{:period}) = Lift(DateTimePeriod)

lookup(ity::Type{DateTimePeriod}, name::Symbol) =
    if name in (:start_time, :stop_time)
        lift(getfield, name) |> designate(ity, DateTime)
    elseif name in (:start, :startTime)
        lift(getfield, :start_time) |> designate(ity, DateTime)
    elseif name in (:stop, :end, :stopTime, :endTime)
        lift(getfield, :stop_time) |> designate(ity, DateTime)
    end

# We define `includes` to mean that a date falls within a date interval
# inclusively, or that one interval is completely subsumed by another.

includes(period::DateTimePeriod, val::String) =
    includes(period, DateTime(val))

includes(period::DateTimePeriod, val::DateTime) =
    period.stop_time >= val >= period.start_time

includes(period::DateTimePeriod, val::DateTimePeriod) =
   (val.start_time >= period.start_date) &&
   (period.stop_time >= val.stop_date)

# we define 

and_previous(init::DateTime, len::Day) =
    DateTimePeriod(init - len, init)
and_subsequent(init::DateTime, len::Day) =
    DateTimePeriod(init, init + len)
and_previous(di::DateTimePeriod, len::Day) =
    DateTimePeriod(di.start_time - len, di.stop_time)
and_subsequent(di::DateTimePeriod, len::Day) =
    DateTimePeriod(di.start_time, di.stop_time + len)

"""
X >> Includes(Y)
This combinator is true if the interval of `Y` is completely included
in the interval for `X`.  That is, if the starting point of `Y` is
greater than or equal to the starting point of `X`, and also if the
ending point of `Y` is less than or equal to the stoping point of `X`.
This combinator accepts a `DateTimePeriod` for its arguments, but also
any object that has `StartDate` and `EndDate` defined.
"""
Includes(Y) = includes.(It, Y)
translate(mod::Module, ::Val{:includes}, args::Tuple{Any}) =
    Includes(translate.(Ref(mod), args)...)

During(Y) = includes.(Y, It)
translate(mod::Module, ::Val{:during}, args::Tuple{Any}) =
    During(translate.(Ref(mod), args)...)

AndPrevious(Y) = and_previous.(It >> DateTimePeriod, Lift(Day, (Y,)))
translate(mod::Module, ::Val{:and_previous}, args::Tuple{Any}) =
    AndPrevious(translate.(Ref(mod), args)...)

AndSubsequent(Y) = and_subsequent.(It >> DateTimePeriod, Lift(Day, (Y,)))
translate(mod::Module, ::Val{:and_subsequent}, args::Tuple{Any}) =
    AndSubsequent(translate.(Ref(mod), args)...)

