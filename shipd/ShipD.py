from pathlib import Path
import sys

par_dir = Path(__file__).resolve().parent.parent

sys.path.append(str(par_dir))


from HullParameterization import Hull_Parameterization
import ModifiedMichellCw
