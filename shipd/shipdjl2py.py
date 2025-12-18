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

jlPath = f"{Path(__file__).parent.parent}/thinShip/"
jl.include(f"{jlPath}/Michell.jl")


class ShipDJL2PY():
    """
    This class file wraps Julia functionality
    """
    def __init__(self):
        pass


    def compute_drag(self, offsets, Uinf, xpos, zpos, rho, Nint=1000):

        Dw, FreeWaveSpectrum = jl.solve_michell(offsets, Uinf, xpos, zpos, rho, Nint)

        Dprof = jl.compute_formdrag(LWL, rho, Uinf, WSA)

        HydroDrag = Dw + Dprof

        return HydroDrag