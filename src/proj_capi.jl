# The following functions are generally named after the associated C API
# functions, but without the pj prefix.


function _init_plus(proj_string::ASCIIString)
    proj_ptr = ccall((:pj_init_plus, libproj), Ptr{Void}, (Cstring,), proj_string)
    if proj_ptr == C_NULL
        # TODO: use context?
        error("Could not parse projection string: \"$proj_string\": $(_strerrno())")
    end
    proj_ptr
end

@doc "Free C datastructure associated with a projection.  For internal use only!" ->
function _free(proj_ptr::Ptr{Void})
    @assert proj_ptr != C_NULL
    ccall((:pj_free, libproj), Void, (Ptr{Void},), proj_ptr)
end

@doc "Get human readable error string from proj.4 error code" ->
function _strerrno(code::Cint)
    bytestring(ccall((:pj_strerrno, libproj), Cstring, (Cint,), code))
end

@doc "Get global errno string in human readable form" ->
function _strerrno()
    _strerrno(unsafe_load(ccall((:pj_get_errno_ref, libproj), Ptr{Cint}, ())))
end

@doc "Get projection definition string in the proj.4 plus format" ->
function _get_def(proj_ptr::Ptr{Void})
    @assert proj_ptr != C_NULL
    opts = 0 # Apparently obsolete argument, not used in current proj source
    bytestring(ccall((:pj_get_def, libproj), Cstring, (Ptr{Void}, Cint), proj_ptr, opts))
end

@doc "Low level interface to libproj transform, allowing user to specify strides" ->
function _transform!(src_ptr::Ptr{Void}, dest_ptr::Ptr{Void}, point_count, point_stride, x, y, z)
    @assert src_ptr != C_NULL && dest_ptr != C_NULL
    ccall((:pj_transform, libproj), Cint,
          (Ptr{Void}, Ptr{Void}, Clong, Cint, Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}),
          src.rep, dest.rep, point_count, point_stride, x, y, z)
end

@doc "Low level interface to libproj transform, taking in (and modifying) an Nx2 or Nx3 array of positions" ->
function _transform!(src_ptr::Ptr{Void}, dest_ptr::Ptr{Void}, position::Array{Float64,2})
    @assert src_ptr != C_NULL && dest_ptr != C_NULL
    npoints, ncomps = size(position)
    if ncomps != 2 && ncomps != 3
        error("position must be Nx2 or Nx3")
    end

    P = pointer(position)
    x = P
    y = P + sizeof(Cdouble)*npoints
    z = (ncomps < 3) ? C_NULL : P + 2*sizeof(Cdouble)*npoints

    if _transform!(src, dest, npoints, 1, x, y, z) != 0
        error("transform error: $(_strerrno(err))")
    end
end

function _is_latlong(proj_ptr::Ptr{Void})
    @assert proj_ptr != C_NULL
    ccall((:pj_is_latlong, libproj), Cint, (Ptr{Void},), proj_ptr) != 0
end

function _is_geocent(proj::Ptr{Void})
    @assert proj_ptr != C_NULL
    ccall((:pj_is_geocent, libproj), Cint, (Ptr{Void},), proj_ptr) != 0
end

@doc "Get a string describing the underlying version of libproj in use" ->
function libproj_version()
    bytestring(ccall((:pj_get_release, libproj), Cstring, ()))
end

@doc "This function converts cartesian (xyz) geocentric coordinates into geodetic (lat/long/alt) coordinates" ->
function _geocentric_to_geodetic!(a::Cdouble, es::Cdouble, point_count, point_offset, x, y, z)
    ccall((:pj_geocentric_to_geodetic, libproj), Cint, (Cdouble, Cdouble, Clong, Cint,
          Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}), a, es, point_count, point_offset, x, y, z)
end

function _geocentric_to_geodetic!(a::Cdouble, es::Cdouble, position::Array{Float64,2})
    npoints, ncomps = size(position)
    if ncomps != 2 && ncomps != 3
        error("position must be Nx2 or Nx3")
    end

    P = pointer(position)
    x = P
    y = P + sizeof(Cdouble)*npoints
    z = (ncomps < 3) ? C_NULL : P + 2*sizeof(Cdouble)*npoints

    err = _geocentric_to_geodetic!(a, es, npoints, 1, x, y, z)
    if err != 0
        error("geocentric_to_geodetic error: $(_strerrno(err))")
    end
    position
end

@doc "This function converts geodetic (lat/long/alt) coordinates into cartesian (xyz) geocentric coordinates" ->
function _geodetic_to_geocentric!(a::Cdouble, es::Cdouble, point_count, point_offset, x, y, z)
    ccall((:pj_geodetic_to_geocentric, libproj), Cint, (Cdouble, Cdouble, Clong, Cint,
          Ptr{Cdouble}, Ptr{Cdouble}, Ptr{Cdouble}), a, es, point_count, point_offset, x, y, z)
end

function _geodetic_to_geocentric!(a::Cdouble, es::Cdouble, position::Array{Float64,2})
    npoints, ncomps = size(position)
    if ncomps != 2 && ncomps != 3
        error("position must be Nx2 or Nx3")
    end

    P = pointer(position)
    x = P
    y = P + sizeof(Cdouble)*npoints
    z = (ncomps < 3) ? C_NULL : P + 2*sizeof(Cdouble)*npoints

    err = _geodetic_to_geocentric!(a, es, npoints, 1, x, y, z)
    if err != 0
        error("geodetic_to_geocentric error: $(_strerrno(err))")
    end
    position
end

@doc """
Fetch the internal definition of the spheroid, and returns the tuple (a, es). Note that
you can compute "b" from eccentricity_squared as:

    b = a * sqrt(1 - es)

""" ->
function _get_spheroid_defn(proj_ptr::Ptr{Void})
    major_axis = Ref{Cdouble}()
    eccentricity_squared = Ref{Cdouble}()
    ccall((:pj_get_spheroid_defn, libproj), Void, (Ptr{Void}, Ptr{Cdouble}, Ptr{Cdouble}),
          proj_ptr, major_axis, eccentricity_squared)
    major_axis[], eccentricity_squared[]
end

@doc "Returns true if the two datums are identical, otherwise false." ->
function _compare_datums(p1_ptr::Ptr{Void}, p2_ptr::Ptr{Void})
    @compat(Bool(ccall((:pj_compare_datums, libproj), Cint, (Ptr{Void}, Ptr{Void}), p1_ptr, p2_ptr)))
end

@doc """
Return the lat/long coordinate system on which a projection is based.
If the coordinate system passed in is latlong, a clone of the same will be returned.
""" ->
function _latlong_from_proj(proj_ptr::Ptr{Void})
    ccall((:pj_latlong_from_proj, libproj), Ptr{Void}, (Ptr{Void},), proj_ptr)
end

# TODO
# void pj_pr_list(projPJ);
# int pj_apply_gridshift( projCtx, const char *, int, 
#                         long point_count, int point_offset,
#                         double *x, double *y, double *z );