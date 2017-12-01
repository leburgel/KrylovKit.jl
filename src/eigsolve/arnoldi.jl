# Arnoldi methods for eigenvalue problems
function eigsolve(A, x₀, howmany::Int, which::Symbol, alg::Arnoldi)
    krylovdim = min(alg.krylovdim, length(x₀))
    maxiter = alg.maxiter
    howmany < krylovdim || error("krylov dimension $(krylovdim) too small to compute $howmany eigenvalues")

    ## FIRST ITERATION: setting up
    numiter = 1
    # Compute arnoldi factorization
    iter = ArnoldiIterator(A, x₀, alg.orth)
    fact = start(iter)
    β = normres(fact)
    tol::eltype(β) = alg.tol
    numops = 1
    while length(fact) < krylovdim
        fact = next!(iter, fact)
        numops += 1
        normres(fact) < tol && break
    end

    # Process
    # allocate storage
    HH = zeros(eltype(fact), krylovdim+1, krylovdim)
    UU = zeros(eltype(fact), krylovdim, krylovdim)

    # initialize
    β = normres(fact)
    m = length(fact)
    H = view(HH, 1:m, 1:m)
    U = view(UU, 1:m, 1:m)
    f = view(HH, m+1, 1:m)
    copy!(U, I)
    copy!(H, rayleighquotient(fact))

    # compute dense schur factorization
    T, U, values = hschur!(H, U)
    by, rev = eigsort(which)
    p = sortperm(values, by = by, rev = rev)
    T, U = permuteschur!(T, U, p)
    scale!(f, view(U,m,:), β)
    converged = 0
    while converged < length(fact) && abs(f[converged+1]) < tol
        converged += 1
    end

    ## OTHER ITERATIONS: recycle
    while numiter < maxiter && converged < howmany
        numiter += 1

        # Determine how many to keep
        keep = div(3*krylovdim + 2*converged, 5) # strictly smaller than krylovdim, at least equal to converged
        if eltype(H) <: Real && H[keep+1,keep] != 0 # we are in the middle of a 2x2 block
            keep += 1 # conservative choice
            keep >= krylovdim && error("krylov dimension $(krylovdim) too small to compute $howmany eigenvalues")
        end

        # Update B by applying U using Householder reflections
        B = basis(fact)
        for j = 1:m
            h, ν = householder(U, j:m, j)
            lmul!(U, h, j+1:krylovdim)
            rmulc!(B, h)
        end

        # Shrink Arnoldi factorization (no longer strictly Arnoldi but still Krylov)
        B[keep+1] = last(B)
        for j = 1:keep
            H[keep+1,j] = f[j]
        end

        # Restore Arnoldi form in the first keep columns
        for j = keep:-1:1
            h, ν = householder(H, j+1, 1:j, j)
            H[j+1,j] = ν
            @inbounds H[j+1,1:j-1] = 0
            lmul!(H, h)
            rmulc!(H, h, 1:j)
            rmulc!(B, h)
        end
        copy!(rayleighquotient(fact), H) # copy back into fact
        fact = shrink!(fact, keep)

        # Arnoldi factorization: recylce fact
        while length(fact) < krylovdim
            fact = next!(iter, fact)
            numops += 1
            normres(fact) < tol && break
        end

        # post process
        β = normres(fact)
        m = length(fact)
        H = view(HH, 1:m, 1:m)
        U = view(UU, 1:m, 1:m)
        f = view(HH, m+1, 1:m)
        copy!(U, I)
        copy!(H, rayleighquotient(fact))

        # compute dense schur factorization
        T, U, values = hschur!(H, U)
        by, rev = eigsort(which)
        p = sortperm(values, by = by, rev = rev)
        T, U = permuteschur!(T, U, p)
        scale!(f, view(U,m,:), β)
        converged = 0
        while converged < length(fact) && abs(f[converged+1]) < tol
            converged += 1
        end
    end
    # Compute eigenvectors
    if eltype(H) <: Real && length(fact) > howmany && T[howmany+1,howmany] != 0
        howmany += 1
    end
    values = schur2eigvals(T, 1:howmany)
    R = schur2eigvecs(T, 1:howmany)
    V = U*R;

    # Compute convergence information
    vectors = let B = basis(fact)
        [B*v for v in cols(V)]
    end
    residuals = let r = residual(fact)
        [r*last(v) for v in cols(V)]
    end
    normreseigvecs = scale!(map(abs, view(V, m, :)), β)

    return values, vectors, ConvergenceInfo(converged, normreseigvecs, residuals, numiter, numops)
end
