#-------------------------------------------------------------------------------

"""
    transform!(src_crs, dest_crs, position [, radians=false])

Transform between coordinate reference systems, modifying `position` in place.

    src_crs  - Source coordinate system definition
    dest_crs - Destination coordinate system definition
    position - An array of coordinates to be transformed in place.  If `position` is a
               Vector of length 2 or 3 it's treated as a single point.  For
               geographic coordinate systems, the first two columns are the
               *longitude* and *latitude*, in that order.  To transform an
               array of points, a matrix of shape Nx2 or Nx3 may be used.
    radians  - If true, treat geographic lon,lat coordinates as radians on
               input and output.

Returns:

    position - Transformed position
"""
function transform!(src::ProjCRS, dest::ProjCRS, position::Array{Float64,2}, radians::Bool=false)
    npoints, ndim = size(position)
    @assert ndim >= 2
    if !radians && is_latlong(src)
        for i=1:npoints
            position[i,1] = deg2rad(position[i,1]); position[i,2] = deg2rad(position[i,2])
        end
    end
    pj_transform!(src.ptr, dest.ptr, position)
    if !radians && is_latlong(dest)
        for i=1:npoints
            position[i,1] = rad2deg(position[i,1]); position[i,2] = rad2deg(position[i,2])
        end
    end
    position
end

"""
    transform(src_csr, dest_csr, position [, radians=false])

Transform between coordinate reference systems, returning the transformed
points in a Float64 array the same shape as `position`.
"""
transform(src::ProjCRS, dest::ProjCRS, position::Array{Float64,2}, radians::Bool=false) =
    transform!(src, dest, copy(position), radians)
transform{T<:Real}(src::ProjCRS, dest::ProjCRS, position::Array{T,2}, radians::Bool=false) =
    transform!(src, dest, map(Float64, position), radians)


function transform!(src::ProjCRS, dest::ProjCRS, position::Vector{Float64}, radians::Bool=false)
    !radians && is_latlong(src) && (position[1] = deg2rad(position[1]); position[2] = deg2rad(position[2]))
    pj_transform!(src.ptr, dest.ptr, position)
    !radians && is_latlong(dest) && (position[1] = rad2deg(position[1]); position[2] = rad2deg(position[2]))
    position
end
transform(src::ProjCRS, dest::ProjCRS, position::Vector{Float64}, radians::Bool=false) =
    transform!(src, dest, copy(position), radians)
transform{T<:Real}(src::ProjCRS, dest::ProjCRS, position::Vector{T}, radians::Bool=false) =
    transform!(src, dest, map(Float64, position), radians)


#-------------------------------------------------------------------------------
# 2D projections
#
# FIXME: These should not really act on ProjCRS objects, as this is quite
# conceptually confusing!  See the README.
#=
"""
Returns the forward projection from LatLon to XY in the given projection,
modifying the input lonlat inplace (only supports 2 dimensions)"""
function lonlat2xy!(lonlat::Vector{Float64}, proj::ProjCRS, radians::Bool=false)
    !radians && (lonlat[:] = deg2rad(lonlat))
    pj_fwd!(lonlat, proj.ptr)
end

function lonlat2xy!(lonlat::Array{Float64,2}, proj::ProjCRS, radians::Bool=false)
    if !radians
        for i in eachindex(lonlat)
            lonlat[i] = deg2rad(lonlat[i])
        end
    end
    pj_fwd!(lonlat, proj.ptr)
end

"Returns the forward projection from LonLat to XY in the given projection (only supports 2 dimensions)"
lonlat2xy(lonlat::Vector{Float64}, proj::ProjCRS, radians::Bool=false) =
    lonlat2xy!(copy(lonlat), proj, radians)
lonlat2xy(lonlat::Array{Float64,2}, proj::ProjCRS, radians::Bool=false) =
    lonlat2xy!(copy(lonlat), proj, radians)

"""
Returns the inverse projection from XY to LonLat in the given projection,
modifying the input xy inplace (only supports 2 dimensions)"""
function xy2lonlat!(xy::Vector{Float64}, proj::ProjCRS, radians::Bool=false)
    pj_inv!(xy, proj.ptr)
    !radians && (xy[1:2] = rad2deg(xy[1:2]))
    xy
end

function xy2lonlat!(xy::Array{Float64,2}, proj::ProjCRS, radians::Bool=false)
    pj_inv!(xy, proj.ptr)
    if !radians
        for i in eachindex(xy)
            xy[i] = rad2deg(xy[i])
        end
    end
    xy
end

"Returns the inverse projection from XY to LatLon in the given projection (only supports 2 dimensions)"
xy2lonlat(xy::Vector{Float64}, proj::ProjCRS, radians::Bool=false) = xy2lonlat!(copy(xy), proj, radians)
xy2lonlat(xy::Array{Float64,2}, proj::ProjCRS, radians::Bool=false) = xy2lonlat!(copy(xy), proj, radians)


#-------------------------------------------------------------------------------
# Geodesic problems on the spheroid.
# FIXME: These should be constructed from an Ellipsoid; interaction with
# ProjCRS should be minimized at this stage.

if has_geodesic_support

    function _geod(proj::ProjCRS)
        if isa(proj.geod, null_geodesic)
            a, es = _get_spheroid_defn(proj.ptr)
            proj.geod = geod_geodesic(a, 1-sqrt(1-es))
        end
        proj.geod
    end

    """
    Solve the direct geodesic problem.

    Args:

        position - coordinates of starting location, modified in-place to [dest] (described below)
        azimuth  - azimuth (degrees) ∈ [-540, 540)
        distance - distance (metres) to move from (lat,lon); can be negative
        proj     - the given projection whose ellipsoid we move along

    Returns:

        dest     - destination after moving for [distance] metres in [azimuth] direction.
        azi      - forward azimuth (degrees) at destination [dest].
    """
    function geod_direct!(position::Vector{Float64}, azimuth::Float64, distance::Float64, proj::ProjCRS)
        xy2lonlat!(position, proj)
        dest, azi = _geod_direct!(_geod(proj), position, azimuth, distance)
        lonlat2xy!(dest, proj), azi
    end

    """
    Solve the direct geodesic problem.

    Args:

        lonlat   - latitude, longitude (degrees) ∈ [-90, 90]
        azimuth  - azimuth (degrees) ∈ [-540, 540)
        distance - distance (metres) to move from (lat,lon); can be negative
        proj     - the given projection whose ellipsoid we move along

    Returns:

        dest     - destination after moving for [distance] metres in [azimuth] direction.
        azi      - forward azimuth (degrees) at destination [dest].

    """
    geod_direct(position::Vector{Float64}, azimuth::Float64, distance::Float64, proj::ProjCRS) =
        geod_direct!(copy(position), azimuth, distance, proj)

    "Returns the destination by moving along the ellipsoid in the given projection"
    geod_destination!(position::Vector{Float64}, azi::Float64, dist::Float64, proj::ProjCRS) = geod_direct!(position, azi, dist, proj)[1]
    geod_destination(position::Vector{Float64}, azi::Float64, dist::Float64, proj::ProjCRS) = geod_destination!(copy(position), azi, dist, proj)

    """
    Solve the inverse geodesic problem.

    Args:

        xy1     - coordinates of point 1 in the given projection
        xy2     - coordinates of point 2 in the given projection
        proj    - the given projection whose ellipsoid we move along

    Returns:

        dist    - distance between point 1 and point 2 (meters).
        azi1    - azimuth at point 1 (degrees) ∈ [-180, 180)
        azi2    - (forward) azimuth at point 2 (degrees) ∈ [-180, 180)

    Remarks:

        If either point is at a pole, the azimuth is defined by keeping the longitude fixed,
        writing lat = 90 +/- eps, and taking the limit as eps -> 0+.
    """
    geod_inverse(xy1::Vector{Float64}, xy2::Vector{Float64}, proj::ProjCRS) =
        _geod_inverse(_geod(proj), xy2lonlat(xy1, proj), xy2lonlat(xy2, proj))

    "Returns the distance between the two points in the given projection"
    geod_distance(p1::Vector{Float64}, p2::Vector{Float64}, proj::ProjCRS) = geod_inverse(p1, p2, proj)[1]

end

=#
