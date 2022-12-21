# Load modules
import matplotlib.pyplot as plt
import cmcrameri.cm as cmc
import cartopy.feature as cf                                                                                                        
from pathlib import Path
import psyplot.project as psy
import sys
import netCDF4 as nc
import numpy as np
import xarray as xr
from iconarray.plot import formatoptions # import plotting formatoptions (for use with psyplot)
import iconarray as iconvis # import self-written modules from iconarray
import iconarray
def info_max_dzdc(hhl, grid_file, lev, dx,verify=False):
    """Print information about maximum z-difference between cells.
    Args:
        hhl (2d np.array):      height of half levels
        grid_file (str):        path to grid file
        poi (pd.DataFrame):     points of interest
        lev (int):              N of level (upwards)
        lats (1d np.array):     latitude
        lons (1d np.array):     longitude
    """

    # load grid file
    grid = iconarray.open_dataset(grid_file)

    # neighbour indeces (3 per cell) in fortran start
    #  at 1, hence subtract 1 to make pythonic
    neighs = grid.neighbor_cell_index.values - 1

    # specified coordinate surface
    surf = hhl[-lev, :]

    if verify:
        ii = 3789
        print(f"--- Value of cell {ii} on level {lev}:")
        print(f"    {surf[ii]:.2f}")

    # for simpler code reading:
    # split neighbour vectors for 1st/2nd/3rd neighbour
    # n0 is just a vector with index as value
    n0 = np.arange(0, len(surf))
    n1 = neighs[0, :]
    n2 = neighs[1, :]
    n3 = neighs[2, :]

    if verify:
        print(f"--- Neighbouring cell indeces:")
        print(f"    {n1[ii]}, {n2[ii]}, {n3[ii]}")
        print(f"--- Neighbouring cell values:")
        print(f"    {surf[n1[ii]]:.2f}, {surf[n2[ii]]:.2f}, {surf[n3[ii]]:.2f}")

 # fill "no-neighbour" cells with itself index (n0) such that
    # calculation of difference to neighbouring cell
    # will access itself and dz = 0

    # a) retrieve indices
    to_fill_n1 = np.where(n1 < 0)[0]
    to_fill_n2 = np.where(n2 < 0)[0]
    to_fill_n3 = np.where(n3 < 0)[0]

    if verify:
        print(f"--- Will fill {len(to_fill_n1)} cells indicating 1st neighbour.")
        print(f"--- Will fill {len(to_fill_n2)} cells indicating 2nd neighbour.")
        print(f"--- Will fill {len(to_fill_n3)} cells indicating 3rd neighbour.")

    # b) fill them
    n1[to_fill_n1] = n0[to_fill_n1]
    n2[to_fill_n2] = n0[to_fill_n2]
    n3[to_fill_n3] = n0[to_fill_n3]

    # create 3 new fields with same shape as "surf"
    # and put value of 1st/2nd/3rd neighbour of cell into cell
    surf_n1 = surf[n1]
    surf_n2 = surf[n2]
    surf_n3 = surf[n3]

    if verify:
        print(f"--- Surface of neighbour 1 at cell {ii}:")
        print(f"    {surf_n1[ii]:.2f}")
        print(f"--- Surface of neighbour 2 at cell {ii}:")
        print(f"    {surf_n2[ii]:.2f}")
        print(f"--- Surface of neighbour 3 at cell {ii}:")
        print(f"    {surf_n3[ii]:.2f}")

    # calculate absolute difference fields
    dz_n1 = np.abs(surf - surf_n1)
    dz_n2 = np.abs(surf - surf_n2)
    dz_n3 = np.abs(surf - surf_n3)
    if verify:
        print(f"--- dz to neighbour 1 at cell {ii}:")
        print(f"    {dz_n1[ii]}")
        print(f"--- dz to neighbour 2 at cell {ii}:")
        print(f"    {dz_n2[ii]}")
        print(f"--- dz to neighbour 3 at cell {ii}:")
        print(f"    {dz_n3[ii]}")

    # finally, determine maximum dz between adjacent cells
    dzdc = np.maximum.reduce([dz_n1, dz_n2, dz_n3])
    max_dzdc = np.max(dzdc)
    max_ii = np.where(dzdc == max_dzdc)[0][0]
    sloang = np.arctan(max_dzdc/dx)*(360./(2.*np.pi))
    print(f'maximum elevation difference between adjacent cells: {max_dzdc}')
    print(f'maximum slope angle: {sloang}')
    if verify:
        print(f"--- maximum dz from cell {ii} to neighbours:")
        print(f"    {dzdc[ii]}")



dom=5
grid_file="/scratch/snx3000/gogerb/processing_chain/icon_inn/2019091300_0_1/icon/input/grid/domain"+str(dom)+"_DOM0"+str(dom)+".nc"
hhl_file = "/scratch/snx3000/gogerb/processing_chain/icon_inn/2019091300_0_1/icon/output2/ICON_DOM0"+str(dom)+"_00000000.nc"
grid_file="/scratch/snx3000/gogerb/processing_chain/icon-summer-500m/2022071800_0_24/icon/input/grid/domain1_DOM01.nc"
hhl_file = "/scratch/snx3000/gogerb/processing_chain/icon-summer-500m/2022071800_0_24/icon/ICON_DOM01_00000000.nc"
lev=1
dx=500
hhl_v=psy.open_dataset(hhl_file)
hhl=hhl_v.z_ifc.values
print(hhl.shape)
val=info_max_dzdc(hhl, grid_file, lev, dx, verify=True)
