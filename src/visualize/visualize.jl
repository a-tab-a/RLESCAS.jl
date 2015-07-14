include("../defines/define_save.jl")
include("../helpers/save_helpers.jl")
include("../helpers/TikzUtils.jl")

include("vis_captions.jl")

using TikzPictures
import PGFPlots: Plots, Axis, GroupPlot

using Obj2Dict

using Base.Test

if !isdefined(:RA_STYLE_MAP)
  const RA_STYLE_MAP = [
    ((ra, h_d) -> ra && abs(h_d) < 5, "mark options={color=gray}, mark=*"),
    ((ra, h_d) -> ra && 5 <= h_d < 30, "mark options={color=orange}, mark=*"),
    ((ra, h_d) -> ra && 30 <= h_d, "mark options={color=red}, mark=*"),
    ((ra, h_d) -> ra && -30 < h_d <= -5, "mark options={color=cyan}, mark=*"),
    ((ra, h_d) -> ra && h_d <= -30, "mark options={color=violet}, mark=*")
    ]
end

if !isdefined(:RESPONSE_STYLE_MAP)
  const RESPONSE_STYLE_MAP = [
    (r -> r == "stay", "mark options={color=black}, mark=-"),
    (r -> r == "follow", "mark options={color=black}, mark=asterisk")
    ]
end

function pgfplotLog(sav::SaveDict)

  tps = TikzPicture[]

  #xy and tz group
  g = GroupPlot(2, 2, groupStyle = "horizontal sep = 2.2cm, vertical sep = 2.2cm")

  #xy
  plotArray = vcat(pplot_line(sav, "wm", "x", "y"),
                   pplot_startpoint(sav, "wm", "x", "y", "top"), # label start point
                   pplot_aircraft_num(sav, "wm", "x", "y", startdist = 3.4)) # label aircraft numbers
  ax = Axis(plotArray,
            xlabel = "x ($(sv_simlog_units(sav, "wm", "x")))",
            ylabel = "y ($(sv_simlog_units(sav, "wm", "y")))",
            title = "XY-Position",
            style = "axis equal,clip mode=individual")
  push!(g, ax)

  #altitude vs time
  plotArray = vcat(pplot_z_label270s(sav), # label270 short
                   pplot_line(sav, "wm", "t", "z"),
                   pplot_startpoint(sav, "wm", "t", "z", "side", overrideangle = 0), # label start point
                   pplot_aircraft_num(sav, "wm", "t", "z", startdist = 3.4)) # label aircraft numbers

  ax = Axis(plotArray,
            xlabel = "time ($(sv_simlog_units(sav, "wm", "t")))",
            ylabel = "h ($(sv_simlog_units(sav, "wm", "z")))",
            title = "Altitude vs. Time",
            style = "clip=false,clip mode=individual")
  push!(g, ax)

  #heading rate vs time
  plotArray = vcat(pplot_aircraft_num(sav, "adm", "t", "psi", fy = padded_diff), # label aircraft numbers
                   pplot_line(sav, "adm", "t", "psi", fy = padded_diff))
  ax = Axis(plotArray,
            xlabel = "time ($(sv_simlog_units(sav, "adm", "t")))",
            ylabel = "psidot ($(sv_simlog_units(sav, "adm", "psi"))/s)",
            title = "Heading Rate vs. Time")
  push!(g, ax)

  #vertical rate vs time
  plotArray = vcat(pplot_aircraft_num(sav, "wm", "t", "vz"), # label aircraft numbers
                   pplot_line(sav, "wm", "t", "vz"))
  ax = Axis(plotArray,
            xlabel = "time ($(sv_simlog_units(sav, "wm", "t")))",
            ylabel = "vh ($(sv_simlog_units(sav, "wm", "vz")))",
            title = "Vertical Rate vs. Time")
  push!(g, ax)

  tp = PGFPlots.plot(g)
  use_geometry_package!(tp, landscape = true)
  use_aircraftshapes_package!(tp)

  push!(tps, tp)

  return tps
end

function pplot_aircraft_num(sav, field::String, xname::String, yname::String;
                            ind_start::Int64 = 1,
                            displaystart::Bool = true,
                            displayend::Bool = true,
                            startdist::Float64 = 2.0,
                            enddist::Float64 = 2.0,
                            scale::Float64 = 0.55,
                            fx::Function = identity,
                            fy::Function = identity)
  #xname = field name of x variable
  #yname = field name of y variable

  d = sav

  plotArray = Plots.Plot[]

  xind = sv_lookup_id(d, field, xname)
  yind = sv_lookup_id(d, field, yname)

  for i = 1 : sv_num_aircraft(d, field)

    xvals = sv_simlog_tdata_f(d, field, i, [], xind)
    yvals = sv_simlog_tdata_f(d, field, i, [], yind)

    # apply user-supplied transformations
    xvals = fx(xvals)
    yvals = fy(yvals)

    if displaystart
      # determine where to put the label for the first: left or right
      x1 = xvals[ind_start]
      y1 = yvals[ind_start]
      x2 = xvals[ind_start + 1]

      #mark aircraft number
      dir = x2 < x1  ? "right" : "left"
      push!(plotArray, Plots.Node("$i", x1, y1,
                                  style = "$(dir)=$(startdist)mm,scale=$(scale),rotate=0"))
    end

    if displayend
      # determine where to put the label for the last: left or right
      xend = xvals[end]
      yend = yvals[end]
      xend_1 = xvals[end - 1]

      #mark aircraft number
      dir = xend_1 < xend  ? "right" : "left"
      push!(plotArray, Plots.Node("$i", xend, yend,
                                  style = "$(dir)=$(enddist)mm,scale=$(scale),rotate=0"))
    end
  end

  return plotArray
end

function pplot_startpoint(sav, field::String, xname::String, yname::String, view::String;
                          overrideangle::Union(Nothing, Real) = nothing,
                          ind_start::Int64 = 1,
                          minwidth::Float64 = 0.65,
                          fx::Function = identity,
                          fy::Function = identity)
  #xname = field name of x variable
  #yname = field name of y variable
  #view = "top" or "side" view of aircraft
  #angle = angle of aircraft in degrees.  Pointing right is 0.  Nothing = auto-determine from first and second points.
  #minwidth = minimum width of aircraft icon in cm

  d = sav

  plotArray = Plots.Plot[]

  xind = sv_lookup_id(d, field, xname)
  yind = sv_lookup_id(d, field, yname)

  for i = 1 : sv_num_aircraft(d, field)

    xvals = sv_simlog_tdata_f(d, field, i, [], xind)
    yvals = sv_simlog_tdata_f(d, field, i, [], yind)

    # apply user-supplied transformations
    xvals = fx(xvals)
    yvals = fy(yvals)

    x1 = xvals[ind_start]
    y1 = yvals[ind_start]

    # determine angle of aircraft if not given
    if overrideangle == nothing
      x2 = xvals[ind_start + 1]
      y2 = yvals[ind_start + 1]

      angle = atan2(y2 - y1, x2 - x1) |> rad2deg
    else
      angle = overrideangle
    end

    #mark aircraft start point
    push!(plotArray, Plots.Node("", x1, y1,
                                style = "aircraft $view,draw=white,thin,fill=black,minimum width=$(minwidth)cm,rotate=$angle"))
    #\node [aircraft top,fill=black,minimum width=1cm,rotate=30] at (0,0) {};
    #\node at (axis cs:-14746.707634583, 8514.015622487) [left=2.0mm,scale=0.55,rotate=0] {2};

  end

  return plotArray
end

function pplot_z_label270s(sav; start_time::Int64 = 0, end_time::Int64 = 50, label_scale::Float64 = 0.45)

  d = sav

  @test start_time < end_time

  plotArray = Plots.Plot[]

  tind = sv_lookup_id(d, "wm", "t")
  zind = sv_lookup_id(d, "wm", "z")
  lind = sv_lookup_id(d, "ra", "label270_short")

  for i = 1:sv_num_aircraft(d, "wm")

    ts = sorted_times(d, "ra", i)
    filter!(t -> start_time <= t <= end_time, ts) #filter based on start/end times

    #short labels
    prev_label = ""

    for t in ts

      label = sv_simlog_tdata(d, "ra", i, t, lind)

      if prev_label != label

        label_ = replace(label, "_", "\\_") #convert underscores to latex escape sequence
        label_ = "\\textbf{$(label_)}"

        dir = closest_is_above(d, t, zind, i) ? "left" : "right" #left=below, right=above

        push!(plotArray,Plots.Node(label_, sv_simlog_tdata_f(d, "wm", i, t, tind),
                                   sv_simlog_tdata_f(d, "wm", i, t, zind),
                                   style="rotate=90,scale=$(label_scale),$dir=2mm,fill=white,rectangle,rounded corners=3pt"))
        prev_label = label

      end
    end
  end

  return plotArray
end

function closest_is_above(sav, t::Int64, z_index::Int64, own_id::Int64)

  d = sav
  h1 = sv_simlog_tdata(d, "wm", own_id, t, z_index)

  hs = Float64[]

  for i = 1:sv_num_aircraft(d, "wm")

    if i != own_id

      h2 = sv_simlog_tdata(d, "wm", i, t, z_index)
      push!(hs,h2-h1)

    end
  end

  minindex = indmin(abs(hs))
  minval = hs[minindex]

  return minval >= 0.0
end

function pplot_line(sav, field::String,
                         x::String,
                         y::String;
                         mark_ra::Bool = true,
                         fx::Function = identity,
                         fy::Function = identity)

  d = sav

  plotArray = Plots.Plot[]

  xind = sv_lookup_id(d, field, x)
  yind = sv_lookup_id(d, field, y)

  for i = 1:sv_num_aircraft(d, field)
    #plot trajectories
    xvals = sv_simlog_tdata_f(d, field, i, [], xind)
    yvals = sv_simlog_tdata_f(d, field, i, [], yind)

    # apply user function transforms
    xvals = fx(xvals)
    yvals = fy(yvals)

    # apply time filters
    # TODO:...

    push!(plotArray,Plots.Linear(xvals, yvals,
                                 style="mark options={color=blue}", mark="*"))

    # RA markings
    if mark_ra
      #mark times of RA active
      t_style_array = get_ra_style(d, i)

      for (times, style) = t_style_array
        if !isempty(times)
          push!(plotArray, Plots.Scatter(xvals[times], yvals[times], style = style))
        end
      end

      #mark times where pilot was following RA
      t_style_array = get_response_style(d, i)

      for (times, style) = t_style_array
        if !isempty(times)
          push!(plotArray,Plots.Scatter(xvals[times], yvals[times], style = style))
        end
      end
    end

  end

  return plotArray
end

function padded_diff(x::Vector{Float64})
  # Numerical differentiation with repeated last element so that output is same length as input

  x1 = diff(x)

  return vcat(x1, x1[end])
end

function get_ra_style(sav, aircraft_number::Int64)

  d = sav
  i = aircraft_number

  active_ind = sv_lookup_id(d, "ra", "ra_active")
  rate_ind = sv_lookup_id(d, "ra", "target_rate")

  t_style_array = (Vector{Int64}, String)[]

  for (f, s) in RA_STYLE_MAP
    #find times where f is valid and tag it with style s
    times = find(x->f(x[active_ind], x[rate_ind]), sv_simlog_tdata(d, "ra", i))
    push!(t_style_array,(times, s))
  end

  return t_style_array #vector of tuples.  each tuple = (times::Vector, style::String)
end

function get_response_style(sav,aircraft_number::Int64)

  d = sav
  i = aircraft_number

  #stochastic linear case
  follow_ind = sv_lookup_id(d, "response", "response", noerrors = true)
  if follow_ind != 0
    t_style_array = (Vector{Int64}, string)[]

    for (f, s) in RESPONSE_STYLE_MAP
      times = find(x->f(x[follow_ra_index]), sv_simlog_tdata(d, "response", i))
      push!(t_style_array,(times, s))
    end

    return t_style_array
  end

  #deterministic PR case
  state_index = sv_lookup_id(d, "response", "state", noerrors = true)
  if state_index != 0
    t_style_array = (Vector{Int64}, String)[]

    for (f, s) in RESPONSE_STYLE_MAP
      times = find(x->f(x[state_index]), sv_simlog_tdata(d, "response", i))
      push!(t_style_array,(times, s))
    end

    return t_style_array
  end
end

function trajPlot{T<:String}(savefiles::Vector{T}; format::String = "TEXPDF")

  map(f -> trajPlot(f, format = format), savefiles)
end

function trajPlot(savefile::String; format::String = "TEXPDF")

  # add suppl info and reload.  This avoids adding suppl info to all files
  add_supplementary(savefile)
  sav = trajLoad(savefile)

  outfileroot = getSaveFileRoot(savefile)
  trajPlot(outfileroot, sav, format = format)

  return savefile
end

function trajPlot(outfileroot::String, d::SaveDict; format::String = "TEXPDF")

  td = TikzDocument()
  tps = pgfplotLog(d)

  cap = string(vis_runtype_caps(d, sv_run_type(d)),
               vis_sim_caps(d),
               vis_runinfo_caps(d))

  add_to_document!(td, tps, cap)

  if format == "TEXPDF"
    outfile = string(outfileroot, ".pdf")
    TikzPictures.save(PDF(outfile), td)
    outfile = string(outfileroot, ".tex")
    TikzPictures.save(TEX(outfile), td)
  elseif format == "PDF"
    outfile = string(outfileroot, ".pdf")
    TikzPictures.save(PDF(outfile), td)
  elseif format == "TEX"
    outfile = string(outfileroot, ".tex")
    TikzPictures.save(TEX(outfile), td)
  else
    warn("trajPlot::Format keyword not recognized. Only these are valid: PDF, TEX, or TEXPDF.")
  end

  return td
end

