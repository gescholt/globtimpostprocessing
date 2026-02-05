"""
    Display Helpers

Shared formatting and display utilities for terminal output.
Used by demo scripts and print functions throughout GlobtimPostProcessing.
"""

"""
    fmt_sci(x::Real; sigdigits=3) -> String

Format a number in scientific notation with the given number of significant digits.
"""
function fmt_sci(x::Real; sigdigits::Int=3)
    return @sprintf("%.*e", sigdigits - 1, x)
end

"""
    fmt_time(t::Real) -> String

Format a time duration: seconds if >= 1.0, milliseconds otherwise.
"""
function fmt_time(t::Real)
    return t >= 1.0 ? @sprintf("%.1fs", t) : @sprintf("%.0fms", t * 1000)
end

"""
    fmt_pct(n::Integer, total::Integer) -> String

Format a count as a percentage of a total.
"""
function fmt_pct(n::Integer, total::Integer)
    total == 0 && return "N/A"
    return @sprintf("%.1f%%", 100.0 * n / total)
end

"""
    print_section(title::String; width::Int=80, io::IO=stdout)

Print a colored section header with a trailing rule line.
"""
function print_section(title::String; width::Int=80, io::IO=stdout)
    line = "─"^max(1, width - length(title) - 4)
    printstyled(io, "\n── $title "; color=:cyan, bold=true)
    printstyled(io, line * "\n"; color=:cyan)
end
