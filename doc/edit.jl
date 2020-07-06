using NarrativeTest
make() = withenv("LINES"=>11, "COLUMNS"=>72) do
             runtests(joinpath("doc/src", ENV["DOCFILE"]), mod=Main)
         end
make()
