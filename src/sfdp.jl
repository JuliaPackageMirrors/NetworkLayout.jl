"""
Using the Spring-Electric model suggested by Yifan Hu
(http://yifanhu.net/PUB/graph_draw_small.pdf)
Forces are calculated as :
        f_attr(i,j) = ||xi - xj||^2 / K ,     i<->j
        f_repln(i,j) = -CK^2 / ||xi - xj|| ,  i!=j
Arguments :
  adj_matrix      Sparse/Full Adjacency matrix of the graph
  tol             Tolerance distance - Minimum distance between 2 nodes
  C, K            Constants that help scale the layout
Output :
  positions       Co-ordinates for the nodes
"""
module SFDP

using GeometryTypes
import Base: start, next, done

immutable Layout{M<:AbstractMatrix, P<:AbstractVector, T<:AbstractFloat}
    adj_matrix::M
    positions::P
    tol::T
    C::T
    K::T
    iterations::Int
end

function Layout{M,N,T}(
        adj_matrix::M, PT::Type{Point{N, T}}=Point{2, Float64};
        startpositions=(2*rand(typ, size(adj_matrix,1)) .- 1),
        tol=1.0, C=0.2, K=1.0, iterations=100
    )
    Layout(adj_matrix, startpositions, T(tol), T(C), T(K), Int(iterations))
end

layout(adj_matrix, dim::Int; kw_args...) = layout(adj_matrix, Point{dim,Float64}; kw_args...)

function layout{M,T,N}(
        adj_matrix::M, typ::Type{Point{N, T}}=Point{2, Float64};
        startpositions = (2*rand(typ, size(adj_matrix,1)) .- 1),
        kw_args...
    )
    layout!(adj_matrix,startpositions;kw_args...)
end

function layout!{M,T,N}(
        adj_matrix::M,
        startpositions::AbstractVector{Point{N, T}};
        kw_args...
    )
    network = Layout(adj_matrix, Point{N,T}; startpositions=startpositions, kw_args...)
    state = start(network)
    while !done(network,state)
        network, state = next(network,state)
    end
    return network.positions
end

function start{M, P, T}(network::Layout{M, P, T})
    (one(T), typemax(T), 0, true, 1, copy(network.positions))
end

function next{M,P,T}(network::Layout{M,P,T}, state)
    step, energy, progress, start, iter, locs0 = state
    K, C, tol, adj_matrix = network.K, network.C, network.tol, network.adj_matrix
    locs = network.positions; locs0 = copy(locs)
    energy0 = energy; energy = zero(energy)
    F = eltype(locs); N = size(adj_matrix,1)
    for i in 1:N
        force = F(0)
        for j in 1:N
            i == j && continue
            if adj_matrix[i,j] == 1
            # Attractive forces for adjacent nodes
                force = force + F(f_attr(locs[i],locs[j],K) * ((locs[j] - locs[i]) / norm(locs[j] - locs[i])))
            else
            # Repulsive forces
                force = force + F(f_repln(locs[i],locs[j],C,K) * ((locs[j] - locs[i]) / norm(locs[j] - locs[i])))
            end
        end
        locs[i] = locs[i] + step * (force / norm(force))
        energy = energy + norm(force)^2
    end
    step, progress = update_step(step, energy, energy0, progress)
    return network, (step, energy, progress, false, iter+1, locs0)
end

function done(network::Layout, state)
    step, energy, progress, started, iter, locs0 = state
    started && return false
    return (
        (iter==network.iterations) ||
        dist_tolerance(network.positions, locs0, network.K, network.tol)
    )
end

# Calculate Attractive force
f_attr(a,b,K) = (norm(a-b)^2) / K
# Calculate Repulsive force
f_repln(a,b,C,K) = -C*(K^2) / norm(a-b)

function update_step{T}(step, energy::T, energy0, progress)
    # cooldown step
    t = T(0.9)
    if energy < energy0
        progress = progress + 1
        if progress >= 5
            progress = 0
            step = step/t
        end
    else
        progress = 0
        step = t * step
    end
    return step, progress
end

function dist_tolerance(locs,locs0,K,tol)
    # check whether the layout is optimal
    for i in 1:size(locs, 1)
        if norm(locs[i]-locs0[i]) >= K*tol
            return false
        end
    end
    return true
end

end #end of module
