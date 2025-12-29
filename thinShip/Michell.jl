# --- Julia 1.11---
"""
@File          :   Michell.jl
@Date created  :   2025/10/01
@Last modified :   2025/12/12
@Author        :   Galen Ng
@Desc          :   Based on the python code from Noah Bagazinski. Originally based off of sample code provided in Douglas Read's 
                   dissertation from the University of Maine (2009): 'A Drag Estimate for Concept Stage Ship Design Optimization'
                   https://digitalcommons.library.umaine.edu/cgi/viewcontent.cgi?referer=&httpsredir=1&article=1509&context=etd


"""

using ReverseDiff, ForwardDiff, ChainRulesCore, FiniteDifferences

const GRAV = 9.807 #[m/s^2]
const ν = 1.189e-6 # [m^2/s] saltwater 15C

const tape_cache = Dict{Tuple{Int},ReverseDiff.GradientTape}() # cache tapes based on input size

function solve_michell(offsets, Uinf, xpos, zpos, ϱ, Nint)
    """

    The free wave spectrum is:

    A(θ) = 2/π (g/U^2) sec^3(θ) ∬ ∂ζ/∂x e^(g/U^2) sec^2(θ)(z - i x cos(θ)) dx dz

    Wave resistance from this is:

    Rw = 1/2 ϱ U^2 ∫ [ ( A(θ)^2 cos^3(θ)) ] dθ

    which is solved based on a double Fourier transform applied to obtain A(θ)

    In the case of multi-hulls, you just add the free wave spectra to each other and re-evaluate the wave resistance integral
        
    A(θ) = ∑ Aⱼ(θ) e^(ik(θ)[xⱼcos(θ) + yⱼsin(θ)])

    Inputs
    ------
    offsets - Y[xidx, zidx]
    xpos - 
        x positions of the offsets
    zpos - 
        Does not work with uneven spacing
    Nint - 
        2000 gives pretty low errors
    """
    T = eltype(offsets) # this is for the AD system

    dz = zpos[2] - zpos[1]
    dx = xpos[2] - xpos[1]

    if size(offsets, 1) % 2 == 0
        throw(
            ErrorException("Need odd number of x stations for Filon integration. You gave $(size(offsets, 1))")
            )
    end

    if size(offsets,1) != length(xpos)
        throw(
            ErrorException("Size of offsets in x direction $(size(offsets, 1)) does not match length of xpos $(length(xpos))")
            )
    end

    L = xpos[end] - xpos[1]

    Nx = length(xpos)
    Nz = length(zpos)

    θm = compute_michspace(Nint)

    k0 = GRAV / Uinf^2 # fundamental wave number at this speed
    Coef = 4 * ϱ * Uinf^2 / π
    asub = sec.(θm) # precompute so it's faster
    k = k0 * asub .^ 2 # oblique wave number

    # ---------------------------
    #   Z integral
    # ---------------------------
    # Tuck's Filon-Trapezoidal rule 1967
    # (better than Simpson and trapezoidal integration for solving Fourier integrals)

    Kδz = k0 * dz * asub .^ 2
    iKδzsq = 1 ./ Kδz .^ 2


    # --- Weights ---
    # Compute for each θ
    w₀ = (exp.(Kδz) .- 1 - Kδz) .* iKδzsq
    wₙ = (exp.(Kδz) + exp.(-Kδz) .- 2) .* iKδzsq # there may be a typo in the thesis
    wN = (exp.(-Kδz) .- 1 + Kδz) .* iKδzsq
    # Sanitize weights to avoid NaNs/Infs in the answer
    wₙ[isinf.(wₙ)] .= 0
    wN[isinf.(wN)] .= 0

    F = zeros(T, Nx, Nint) # F(x,θ)
    dF::T = zero(T)
    for ii in 1:Nint
        for jj in 1:Nx
            dF = 0.0
            for kk in 2:Nz-1
                dF += wₙ[ii] * offsets[jj, kk] * exp(k0 * zpos[kk] * asub[ii]^2) * dz
            end
            dF += w₀[ii] * offsets[jj, 1] * exp(k0 * zpos[1] * asub[ii]^2) * dz
            dF += wN[ii] * offsets[jj, end] * exp(k0 * zpos[end] * asub[ii]^2) * dz

            F[jj, ii] = dF
        end
    end

    # ---------------------------
    #   X integral
    # ---------------------------
    # Standard Filon integration method
    κ = k0 * dx * asub
    sin2κ = sin.(2 * κ)
    cos2κ = cos.(2 * κ)
    α = 1 ./ κ .^ 3 .* (κ .^ 2 + 0.5 * κ .* sin2κ + cos2κ .- 1)
    β = 1 ./ κ .^ 3 .* (3 * κ + κ .* cos2κ - 2 * sin2κ)
    γ = 4 ./ κ .^ 3 .* (sin.(κ) - κ .* cos.(κ))
    neven = (Nx + 1) / 2
    nodd = (Nx - 1) / 2
    PT = zeros(T, Nint)
    QT = zeros(T, Nint)
    P = zeros(T, Nint)
    Q = zeros(T, Nint)
    evenIdx::Int64 = 2
    oddIdx::Int64 = 2
    for ii in 1:Nint
        C2n = 0
        S2n = 0
        C2nm1 = 0
        S2nm1 = 0
        for jj in 1:1:neven
            evenIdx = 2 * jj - 1
            C2n += F[evenIdx, ii] * cos(k0 * xpos[evenIdx] * asub[ii])
            S2n += F[evenIdx, ii] * sin(k0 * xpos[evenIdx] * asub[ii])
        end
        for jj in 1:1:nodd
            oddIdx = 2 * jj
            C2nm1 += F[oddIdx, ii] * cos(k0 * xpos[oddIdx] * asub[ii])
            S2nm1 += F[oddIdx, ii] * sin(k0 * xpos[oddIdx] * asub[ii])
        end

        # Transom
        PT[ii] = F[end, ii] * cos(k0 * L * asub[ii])
        QT[ii] = F[end, ii] * sin(k0 * L * asub[ii])

        C2n -= 0.5 * PT[ii]
        S2n -= 0.5 * QT[ii]

        P[ii] = (α[ii] * QT[ii] + β[ii] * C2n + γ[ii] * C2nm1) * dx
        Q[ii] = (-α[ii] * PT[ii] + β[ii] * S2n + γ[ii] * S2nm1) * dx
    end

    # --- Free wave spectrum ---
    Aθ = 2 / π * (im * k .^ 2 .* (P + im * Q) + k .* sec.(θm) .* (PT + im * QT))
    # Aθ = zeros(T, Nint)
    # Aθ_re = real(Aθ)
    # Aθ_im = imag(Aθ)


    # ---------------------------
    #   Theta integral
    # ---------------------------

    # Trapezoidal integration
    secondTerm = k .^ 2 .* (P .^ 2 + Q .^ 2) + 2 * k .* asub .* (Q .* PT - P .* QT) + asub .^ 2 .* (PT .^ 2 + QT .^ 2)
    Rw = Coef * k .^ 2 ./ asub .^ 3 .* secondTerm
    # Replace Nans with zeros
    Rw[isnan.(Rw)] .= 0.0

    RwInt = 0.0
    for ii in 1:Nint-1
        dθ = θm[ii+1] - θm[ii]
        RwInt += 0.5 * (Rw[ii] + Rw[ii+1]) * dθ
    end

    return RwInt, Aθ
end

function solve_waveDrag(vecoffsets, Uinf, xpos, zpos, ϱ, Nint)
    """
    Wrapper so it works with vector inputs for AD
    """

    offsets = reshape(vecoffsets, length(xpos), length(zpos))

    Rw, _ = solve_michell(offsets, Uinf, xpos, zpos, ϱ, Nint)

    return Rw
end

function compute_MichellDerivative(offsets, Uinf, xpos, zpos, ϱ, Nint, mode="RAD")
    """
    Compute the Jacobian of the wave resistance with respect to the offsets
    """

    function get_or_make_tape(func, x₀)
        key = (length(x₀),)
        if haskey(tape_cache, key)
            return tape_cache[key]
        else
            println("Compiling new tape for size ", key)
            tComp = @time begin
                tape = ReverseDiff.GradientTape(func, x₀)
                ReverseDiff.compile(tape)
            end
            tape_cache[key] = tape
            return tape
        end
    end

    if mode == "FAD"
        tFAD = @time begin
            ∇fFAD = ForwardDiff.gradient(x -> solve_waveDrag(x, Uinf, xpos, zpos, ϱ, Nint), vec(offsets))
            return ∇fFAD
        end
    elseif mode == "RAD"
        tRAD = @time begin
            
            # Recording the tape once before and reusing speeds up by like 5x for a test problem
            tape = get_or_make_tape(x -> solve_waveDrag(x, Uinf, xpos, zpos, ϱ, Nint), vec(offsets))

            grad = similar(vec(offsets))
            ReverseDiff.gradient!(grad, tape, vec(offsets))

            return grad
        end
        # println("From scratch")
        # tRAD = @time begin


        #     grad = ReverseDiff.gradient(x->solve_waveDrag(x, Uinf, xpos, zpos, ϱ, Nint), vec(offsets))

        #     return grad
        # end
    elseif mode == "FD"
        tFD = @time begin

            ∇fFD = FiniteDifferences.jacobian(central_fdm(3, 1), x -> solve_waveDrag(x, Uinf, xpos, zpos, ϱ, Nint), vec(offsets))

            return ∇fFD
        end
    end
end

function trapzInt(integrand)
    # TODO: take this from DCFoil to avoid repeated code
end

function compute_wavepattern(AθHalf, Uinf, xRange, yRange)
    """
    Havelock's relation to compute the steady wave pattern

    ζ = Re ∫ A(θ)e^(-ik(θ)[x cosθ + y sinθ]) dθ
    """
    T = eltype(AθHalf) # for AD compatibility

    k0 = GRAV / Uinf^2


    function compute_integrand(Aθn, θ, x, y)

        Z = Aθn * exp(-im * k0 * sec(θ)^2 * (x * cos(θ) + y * sin(θ)))

        return Z
    end

    NintHalf = length(AθHalf)
    θmHalf = compute_michspace(NintHalf)

    θm = vcat(-reverse(θmHalf), θmHalf[2:end])
    Aθ = vcat(reverse(AθHalf), AθHalf[2:end])
    Nint = length(θm)


    ζ = zeros(T, length(xRange), length(yRange))

    for (ix, xval) in enumerate(xRange)

        for (iy, yval) in enumerate(yRange)

            ζInt = 0
            # This integration is from -π/2 to π/2
            for ii in range(1, Nint - 1)
                dθ = θm[ii+1] - θm[ii]

                I1 = compute_integrand(Aθ[ii], θm[ii], xval, yval)
                I2 = compute_integrand(Aθ[ii+1], θm[ii+1], xval, yval)
                ζInt += 0.5 * (I1 + I2) * dθ
            end

            ζ[ix, iy] = ζInt

        end
    end

    return ζ
end

function compute_michspace(Nint)
    """
    Log spacing for angles [0, π/2]
    Bunch near π/2

    Cosine spacing may be better for greater than 500 angles
    """
    # logspace from 0 --> 9
    logspace = 10 .^ LinRange(0, 1, Nint) .- 1
    θm = -logspace[end:-1:1] * π / 18 .+ π / 2

    # # full cosine spacing
    # θm = 0.5 * (1 .- cos.(LinRange(0, 1, Nint) * π))

    # # Half cosine spacing
    # θm = -cos.(LinRange(0, 1, Nint) * π / 2 .+ π / 2)

    return θm
end

function compute_formdrag(LWL, B, T, ϱ, Uinf, WSA, CB)
    """
    Also predict form drag
    Form drag is the sum of skin friction and the pressure drag if there were no free surface
    """
    Re = Uinf * LWL / ν

    # ITTC 1957
    Cf = 0.075 / (log10(Re) - 2)^2

    # Holtrop
    # onePlusK = c13 * (0.93 + c12 * (B / L)^0.92497 * (0.95 - CP)^(-0.521448) * (1 - CP + 0.0225 * LCB)^0.6906)

    # ITTC formula 
    k = 0.11 + 0.128 * B / T - 0.0157 * (B / T)^2 - 3.10 * CB / (LWL / B) + 28.8 * (CB / (LWL / B))^2

    Dform = Cf * (1 +k) * (0.5 * ϱ * Uinf^2 * WSA)

    return Dform
end

function compute_shipWSA(offsets, xpos, ypos)
    """
    Compute wetted surface area from offsets (remember, half a ship, half a grade)
    TODO GWN: WIP 
    """
    for Xpt in eachrow(offsets)
    end
end
