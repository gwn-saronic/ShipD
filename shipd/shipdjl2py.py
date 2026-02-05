# --- Python 3.12 ---
"""
@File          :   shipdjl2py.py
@Date created  :   2025-12-03
@Last modified :   2025-12-03
@Author        :   Galen W. Ng
@Desc          :   Interface to Julia code
"""

# ==============================================================================
# Standard Python modules
# ==============================================================================
from pathlib import Path

# ==============================================================================
# External Python modules
# ==============================================================================
import numpy as np
import juliacall

jl = juliacall.newmodule("ShipD")

jlPath = f"{Path(__file__).parent.parent}/src/"
jl.include(f"{jlPath}/Michell.jl")


class ShipDJL2PY:
    """
    This class file wraps Julia functionality
    """

    def __init__(self):
        pass

    def compute_drag(
        self,
        WSA: float,
        offsets,
        Uinf: float,
        xpos,
        zpos,
        rho: float,
        Nint=1000,
        CB=0.7,
    ):
        """ 
        Make sure these are transposed from what the Julia code expects
         - offsets (incoming shape nDraft x nStations)
         - xpos
         - zpos
        """
        self.Dw, self.FreeWaveSpectrum = jl.solve_michell(
            offsets, Uinf, xpos, zpos, rho, Nint
        )

        LWL = xpos[-1] - xpos[0]
        B = np.max(offsets) * 2
        T = np.max(np.abs(zpos))

        Dvisc = jl.compute_formdrag(LWL, B, T, rho, Uinf, WSA, CB)

        HydroDrag = self.Dw + Dvisc

        return HydroDrag
    
    def compute_wavepattern(self):
        """
        Take the free wave spectrum and compute the wave pattern for visualization
        """

    def compute_hydrostatics(self, mass_properties):
        """
        Compute hydrostatic properties from the offsets
        """

        # ---------------------------
        #   Run simple hydrostatics command first
        # ---------------------------

        # ---------------------------
        #   Get form coefficients
        # ---------------------------

        # ---------------------------
        #   Solve equilibrium
        # ---------------------------

        # ---------------------------
        #   Do static stability calcs
        # ---------------------------

# Test code
if __name__ == "__main__":
    Solver = ShipDJL2PY()

    WSA = 100.0
    LWL = 10.0
    T = 2.0
    xpos = np.linspace(0, LWL, 11)
    zpos = np.linspace(0, -T, 8)
    Uinf = 5.0
    rho = 1000.0
    B = 2.0
    C = 1.0

    X, Z = np.meshgrid(xpos, zpos)

    def analytical_offset(x, z):
        offsets = B / 2 * np.sin(np.pi * C * x / LWL) * np.cos(np.pi * z / (2 * T))
        return offsets

    offsets = analytical_offset(X, Z) 

    Drag = Solver.compute_drag(WSA, offsets.T, Uinf, xpos.T, zpos.T, rho, Nint=1000, CB=0.8)

    print(f"Total Drag: {Drag} N")
