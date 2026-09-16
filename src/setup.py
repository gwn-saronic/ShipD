# --- Python 3.11 ---
"""
@File          :   setup_thinship.py
@Date created  :   2026-08-18
@Last modified :   2026-08-28
@Author        :   Galen W. Ng
@Desc          :   Use AD'ed thin ship analysis
                   Michell (1898); see also Tuck (1987) for the wave resistance theory
"""

import os

import numpy as np
from scipy.interpolate import RegularGridInterpolator

PT_SET_NAME = "thinship"


def read_plot3d_surface_block(fileName, blockIndex):
    """
    Read one block of a multi-block ASCII PLOT3D surface file (nk=1) into
    station/waterline arrays. Mirrors the reshape convention in
    ../ShipShape/gen_FFD.py:read_ffd, generalized to multiple blocks.

    Assumes a tensor grid where x is constant along j and z is constant along i
    (true for wigley.xyz by construction in ../Meshing/make_wigley.py).

    Returns
    -------
    x1d : (Ni,) station x positions
    z1d : (Nj,) waterline z positions
    y2d : (Ni, Nj) half-beam offsets
    """
    with open(fileName) as f:
        nBlocks = int(f.readline())
        dims = [tuple(int(n) for n in f.readline().split()) for _ in range(nBlocks)]
        if not (0 <= blockIndex < nBlocks):
            raise ValueError(f"{fileName} has {nBlocks} blocks; blockIndex={blockIndex} is invalid")
        data = np.array(f.read().split(), dtype=float)

    offset = 0
    for bi, (ni, nj, nk) in enumerate(dims):
        nPts = ni * nj * nk
        if bi == blockIndex:
            block = data[offset : offset + 3 * nPts].reshape(3, nk, nj, ni).transpose(3, 2, 1, 0)
            break
        offset += 3 * nPts

    x1d = block[:, 0, 0, 0]
    z1d = block[0, :, 0, 2]
    y2d = block[:, :, 0, 1]
    return x1d, z1d, y2d


class ThinShipWaveDrag:
    """
    Michell thin-ship wave-drag evaluator wired to a DVGeo pointset, with
    gradients via the reverse-mode AD in ShipD and DVGeo.totalSensitivity.

    A uniform (x, z) grid of hull-surface points is embedded in the FFD once at
    setup; after each DVGeo.setDesignVars the deformed y coordinates are the
    half-beam offsets the Michell integral consumes. The FFD only moves points
    in y, so the station/waterline positions are cached at setup.
    """

    def __init__(self, comm, DVGeo, hullSurfFile, nStations=121, nWaterlines=41, blockIndex=0, Nint=1000, CB=0.7):
        self.comm = comm
        self.DVGeo = DVGeo
        self.nStations = nStations
        self.nWaterlines = nWaterlines
        self.Nint = Nint
        self.CB = CB

        xHull, zHull, yHull = read_plot3d_surface_block(hullSurfFile, blockIndex)

        # The Filon quadrature in the Michell solver requires an odd number of
        # uniformly spaced stations and uniform waterline spacing, so the
        # clustered CFD surface grid cannot be used directly
        if nStations % 2 == 0:
            raise ValueError(f"nStations must be odd for Filon integration; got {nStations}")
        self.xpos = np.linspace(xHull.min(), xHull.max(), nStations)
        self.zpos = np.linspace(zHull.max(), zHull.min(), nWaterlines)  # waterline (0) -> keel (-T)

        # Linear interpolation avoids spline overshoot near the bow/stern where
        # the offsets taper to the meshing seam-thickness floor
        interpolateOffsets = RegularGridInterpolator((xHull, zHull), yHull, method="linear")
        Xq, Zq = np.meshgrid(self.xpos, self.zpos, indexing="ij")
        baselineOffsets = np.abs(interpolateOffsets(np.stack([Xq.ravel(), Zq.ravel()], axis=-1)))

        # Ordered so pts[:, 1].reshape(nStations, nWaterlines) recovers the
        # Y[xidx, zidx] layout solve_michell expects. Embed on every rank so
        # DVGeo state stays uniform across the member communicator
        coords = np.column_stack([Xq.ravel(), baselineOffsets, Zq.ravel()])
        DVGeo.addPointSet(coords, PT_SET_NAME)

        # Only rank 0 pays the Julia runtime startup; the wave drag is a cheap
        # scalar we broadcast after evaluation
        self.michellSolver = None
        if comm.rank == 0:
            from shipd import ShipDJL2PY

            self.michellSolver = ShipDJL2PY()

    def evalFunctions(self, ap, funcs):
        """
        Evaluate the Michell wave resistance for the current design and add it
        to funcs as f"{ap.name}_wave_drag". Mirrors CFDSolver.evalFunctions.
        The caller must have already applied the design variables with
        DVGeo.setDesignVars.
        """
        waveDrag = None

        if self.comm.rank == 0:
            pts = self.DVGeo.update(PT_SET_NAME)
            offsets = np.abs(pts[:, 1]).reshape(self.nStations, self.nWaterlines)

            # WSA=0 zeroes the ITTC form-drag term inside compute_drag so only
            # the pure Michell wave resistance (Dw) is kept; the CFD drag
            # already carries the viscous and form contributions
            self.michellSolver.compute_drag(
                0.0, offsets, ap.V, self.xpos, self.zpos, ap.rho, Nint=self.Nint, CB=self.CB
            )
            waveDrag = float(self.michellSolver.Dw)

        waveDrag = self.comm.bcast(waveDrag, root=0)  # Broadcast to all procs
        funcs[f"{ap.name}_wave_drag"] = waveDrag

    def evalFuncSens(self, ap, funcsSens):
        """
        Total derivative of the Michell wave resistance wrt the geometric
        design variables, added to funcsSens as f"{ap.name}_wave_drag".
        Mirrors CFDSolver.evalFunctionsSens.
        """
        nPts = self.nStations * self.nWaterlines
        dIdPts = np.zeros((1, nPts, 3))

        if self.comm.rank == 0:
            pts = self.DVGeo.update(PT_SET_NAME)
            offsets = np.abs(pts[:, 1]).reshape(self.nStations, self.nWaterlines)

            dDragdOffsets = np.asarray(
                self.michellSolver.compute_dragDerivative(
                    offsets, ap.V, self.xpos, self.zpos, ap.rho, Nint=self.Nint, mode="RAD"
                )
            )
            # The Julia side differentiates wrt vec(offsets), which flattens
            # the (nStations, nWaterlines) matrix column-major
            dDragdOffsets = dDragdOffsets.reshape((self.nStations, self.nWaterlines), order="F")

            # sign() is the chain rule through the abs() in evalFunctions
            dIdPts[0, :, 1] = dDragdOffsets.ravel() * np.sign(pts[:, 1])

        # Non-root ranks contribute zeros, so the allreduce inside
        # totalSensitivity leaves only the rank-0 evaluation
        dDragdDVs = self.DVGeo.totalSensitivity(dIdPts, PT_SET_NAME, comm=self.comm)

        # Flatten (1, nDV) -> (nDV,) to match the CFDSolver.evalFunctionsSens convention
        funcsSens[f"{ap.name}_wave_drag"] = {key: np.asarray(val).reshape(-1) for key, val in dDragdDVs.items()}

    def writeWavePattern(self, ap, outputDir, xRange, yRange, iterNum):
        """
        Havelock wave pattern (free-surface elevation) from the free wave
        spectrum of the last evalFunctions call, written to
        <outputDir>/wave_pattern_<ap.name>_<iterNum>.npz. The caller must have already
        called evalFunctions for this design so the spectrum is current.
        """
        if self.comm.rank == 0:
            zeta = self.michellSolver.compute_wavepattern(ap.V, xRange, yRange)
            # Havelock's relation keeps only the real part of the theta integral
            zeta = np.real(np.asarray(zeta))
            np.savez(
                os.path.join(outputDir, f"{ap.name}_{iterNum:03d}_wave_pattern.npz"),
                x=xRange,
                y=yRange,
                zeta=zeta,
            )
        self.comm.Barrier()


def setup(args, comm, DVGeo, files):
    """
    Use a pointset embedded in DVGeo as the input to the thin ship code.
    Doing it this way allows for sensitivity calls of the wave drag later.
    """

    WaveDragSolver = ThinShipWaveDrag(comm, DVGeo, files["hullSurfFile"])

    return WaveDragSolver

