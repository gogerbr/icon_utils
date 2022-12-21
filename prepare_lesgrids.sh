#!/bin/bash

# Gather files to run an ICON-1 simulation for a specific date
# Author: Stephanie Westerhuis
# Date: July 15, 2022
 
# Usage:
# /path/to/prepare_case_study.sh YYMMDDHH
# /users/swester/runscripts/prepare_case_study.sh 22011800

# Load spack first
# module load cray-python
# source /project/g110/spack/user/daint/spack/share/spack/setup-env.sh

# Adaptations by Nadja Omnanovic (ETHZ) - 10-2022:
# This script creates IC and BC based on COSMO ANA files. In both
# map_file.latbc and ana_varnames_map_file.txt HHL needs to be
# changed to HEIGHT, so ICON recognizes the variable.

#####################################################################

# specifications
# --------------

# fieldextra
if [[ `hostname` == nid* ]]; then
    #fieldextra=~tsm/manali/fieldextra/develop/bin/fieldextra_gnu_opt_omp
    fieldextra=~tsm/manali/fieldextra/develop/src/fieldextra_gnu_opt_omp
    scr=/scratch/e1000/mch/$USER
elif [[ `hostname` == tsa* ]]; then
    fieldextra=/project/s83c/fieldextra/tsa/bin/fieldextra_gnu_opt_omp
    scr=/scratch/$USER
elif [[ `hostname` == daint* ]]; then
    fieldextra=/project/s83c/fieldextra/daint/bin/fieldextra_gnu_opt_omp
    pr=/store/g142/gogerb/icon_input/cases/icon_inn/grid/les_grids/

else
    echo "No fieldextra executable specified for your machine."
    exit 1
fi

# default leadtime
default_lt=2

# test user input
# ---------------

# did user specify any arguments at all?
if [[ "$#" -lt 1 ]]; then
    echo "You forgot to specify a date: YYMMDDHH"
    exit 1
else
    date=$1
fi

# does format of date look reasonable?
if [[ "${#date}" -ne 8 ]]; then
    echo "Format of specified date seems wrong: YYMMDDHH."
    exit 1
fi

# has leadtime been specified?
if [[ "${#2}" -lt 1 ]]; then
    leadtime=$default_lt
    echo "Use default leadtime: ${default_lt}"
else 
    leadtime=$2
fi

# prepare date variables
yy=${date:0:2}
mm=${date:2:2}
dd=${date:4:2}
hh=${date:6:2}
hl=$((${hh}+${leadtime}))
echo "Prepare case study for 20${yy} ${mm} ${dd}, ${hh} UTC: +${leadtime}h"

# create working directory
# ------------------------
wd=${pr}/20$date
mkdir -p $wd
cd $wd
#rm fx_prepare_??.nl

# write fieldextra namelists
# --------------------------

# header of ic fx-namelist
cat << EOF > fx_prepare_ic.nl
!##############################################
! Regrid input files to ICON-1 grid
!##############################################
! fish

&RunSpecification
 strict_usage          = .true.
 verbosity             = "moderate"
 additional_diagnostic = .false.
 additional_profiling  = .false.
 n_ompthread_total     = 12
 n_ompthread_collect   = 1
 n_ompthread_generate  = 1
/

EOF

# copy header also for bc fx-namelist
cp fx_prepare_ic.nl fx_prepare_bc.nl

# content for ic regridding
cat << EOF >> fx_prepare_ic.nl
!----------------------------------------------------------------------------------
! COSMO data is decoded with the help of dictionary_cosmo, and encoded as ICON data 
! using dictionary_icon. Therefore, both dictionaries have to be specified.
!----------------------------------------------------------------------------------
&GlobalResource
 dictionary            = "/project/s83c/fieldextra/daint/resources/dictionary_icon.txt",
                         "/project/s83c/fieldextra/daint/resources/dictionary_cosmo.txt"
 grib_definition_path  = "/project/s83c/fieldextra/daint/resources/eccodes_definitions_cosmo",
                         "/project/s83c/fieldextra/daint/resources/eccodes_definitions_vendor"
 grib2_sample          = "/project/s83c/fieldextra/daint/resources/eccodes_samples/COSMO_GRIB2_default.tmpl"
 icon_grid_description = "/store/g142/gogerb/icon_input/cases/icon_inn/grid/domain3_DOM03.nc"
/

!----------------------------------------------------------------------------------
! COSMO is set as the default_model_name here, but since in_model_name and
! out_model_name are explicitely set in the I/O blocks, the default_model_name is
! actually not used in this example.
!----------------------------------------------------------------------------------
&GlobalSettings
  default_model_name            = "icon"
  !default_out_type_stdlongitude = .true.
/

!----------------------------------------------------------------------------------
! The specification of the wilting_point and the field_capacity for the soil_types of
! the COSMO model is required for the computation of the soil moisture index.
!----------------------------------------------------------------------------------
&ModelSpecification
 model_name         = "cosmo"
 earth_axis_large   = 6371229.
 earth_axis_small   = 6371229.
 soil_types(:)%code           =  1    , 2     , 3     , 4           , 5     , 6           , 7     , 8     , 9    , 10       ,
 soil_types(:)%name           =  "ice", "rock", "sand", "sandy_loam", "loam", "loamy_clay", "clay", "peat", "sea", "sea_ice",
 soil_types(:)%wilting_point  =  0.   , 0.    , 0.042 , 0.100       , 0.110 , 0.185       , 0.257 , 0.265 , 0.   , 0.       ,
 soil_types(:)%field_capacity =  0.   , 0.    , 0.196 , 0.260       , 0.340 , 0.370       , 0.463 , 0.763 , 0.   , 0.       ,
/

!----------------------------------------------------------------------------------
! Radial basis function interpolation will be used as regrid_method to the ICON triangular 
! grid for all fields. 
!----------------------------------------------------------------------------------
&ModelSpecification
  model_name                = "icon"
  snow_levels_positive      = "up"
  earth_axis_large          = 6371229.
  earth_axis_small          = 6371229.
  regrid_method             = "__ALL__:icontools,rbf"
/

!----------------------------------------------------------------------------------
! Use INCORE storage to tag the COSMO mass point grid for the re-gridding of U and V 
!----------------------------------------------------------------------------------
&Process
!  in_file = "/store/s83/osm/KENDA-1/ANA${yy}/det/laf20${date}"
  in_file = "/store/g142/gogerb/icon_input/cases/icon_inn/icbc/laf20${date}"
  in_model_name="cosmo"
  out_type = "INCORE"
/
&Process in_field = "HSURF", tag="GRID_cosmo" /

!----------------------------------------------------------------------------------
! Read all necessary input from the KENDA-1 analysis as COSMO data.
! Re-grid U and V on input, and rotate them with respect to the geographical reference system.
! Set T_ICE to 0.
! Create FR_ICE from FR_LAND, and set the field to 0.
! Data will be re-gridded on output to the cell subgrid of the ICON triangular grid, which is
! specified in /project/s83c/fieldextra/tsa/resources/grid_descriptions/ICON-1E_DOM01_R19B08.nc. Note that out_model_name
! is set in the programme before the re-gridding takes place. Thus the default regrid_method that
! is defined in the ModelSpecification of ICON is used (and must be defined there).
!----------------------------------------------------------------------------------
&Process
 ! in_file = "/store/s83/osm/KENDA-1/ANA${yy}/det/laf20${date}"
  in_file = "/store/g142/gogerb/icon_input/cases/icon_inn/icbc/laf20${date}"
  in_model_name="cosmo"
  in_regrid_target="GRID_cosmo", in_regrid_method="average,square,0.9"
  out_regrid_target = "icon_grid,cell,/store/g142/gogerb/icon_input/cases/icon_inn/grid/domain3_DOM03.nc"
  out_regrid_method = "default"
  out_model_name = "icon"
  out_file = "${wd}/dom03_laf20${date}.nc",
  out_type = "NETCDF", out_type_ncaspect="icon", out_type_nousetag=.true., out_type_nccoordbnds=.true.
  out_mode_smi_clipped=.f.
/
&Process in_field="HEIGHT", level_class="k_half", levmin=1, levmax=81 /
&Process in_field="U", levmin=1, levmax=80, regrid=.t., poper="n2geog" /
&Process in_field="V", levmin=1, levmax=80, regrid=.t., poper="n2geog" /
&Process in_field="W", levmin=1, levmax=81 /
&Process in_field="T", levmin=1, levmax=80 /
&Process in_field="P", levmin=1, levmax=80 /
&Process in_field="QV", levmin=1, levmax=80 /
&Process in_field="QC", levmin=1, levmax=80 /
&Process in_field="QI", levmin=1, levmax=80 /
&Process in_field="QR", levmin=1, levmax=80 /
&Process in_field="QS", levmin=1, levmax=80 /
&Process in_field="QG", levmin=1, levmax=80 /
&Process in_field="T_G" /
&Process in_field="T_ICE", poper="replace_all,273.15" /
&Process in_field="H_ICE" /
&Process in_field="T_MNW_LK" /
&Process in_field="T_WML_LK" /
&Process in_field="H_ML_LK" /
&Process in_field="T_BOT_LK" /
&Process in_field="C_T_LK" /
&Process in_field="QV_S" /
&Process in_field="T_SO" /
&Process in_field="FRESHSNW" /
&Process in_field="RHO_SNOW" /
&Process in_field="T_SNOW" /
&Process in_field="W_SNOW" /
&Process in_field="H_SNOW" /
&Process in_field="W_I" /
&Process in_field="Z0" /
&Process in_field="FR_LAND", poper="replace_all,0.", new_field_id="FR_ICE" /
&Process in_field="W_SO_ICE" /
&Process in_field = "W_SO" /
&Process in_field = "SOILTYP" /

!----------------------------------------------------------------------------------
! Compute the SMI, and filter W_SO and SOILTYP.
!----------------------------------------------------------------------------------
&Process out_field="HEIGHT", level_class="k_half", levmin=1, levmax=81 /
&Process out_field="U", levmin=1, levmax=80 /
&Process out_field="V", levmin=1, levmax=80 /
&Process out_field="W", levmin=1, levmax=81 /
&Process out_field="T", levmin=1, levmax=80 /
&Process out_field="P", levmin=1, levmax=80 /
&Process out_field="QV", levmin=1, levmax=80 /
&Process out_field="QC", levmin=1, levmax=80 /
&Process out_field="QI", levmin=1, levmax=80 /
&Process out_field="QR", levmin=1, levmax=80 /
&Process out_field="QS", levmin=1, levmax=80 /
&Process out_field="QG", levmin=1, levmax=80 /
&Process out_field="T_G" /
&Process out_field="T_ICE" /
&Process out_field="H_ICE" /
&Process out_field="T_MNW_LK" /
&Process out_field="T_WML_LK" /
&Process out_field="H_ML_LK" /
&Process out_field="T_BOT_LK" /
&Process out_field="C_T_LK" /
&Process out_field="QV_S" /
&Process out_field="T_SO" /
&Process out_field="FRESHSNW" /
&Process out_field="RHO_SNOW" /
&Process out_field="T_SNOW" /
&Process out_field="W_SNOW" /
&Process out_field="H_SNOW" /
&Process out_field="W_I" /
&Process out_field="Z0" /
&Process out_field="FR_ICE" /
&Process out_field="W_SO_ICE" /
&Process out_field="SMI" /

EOF

# -----------------------------------------------
# lateral boundary grid
# -----------------------------------------------
# if string is "" -> create lateral boundary grid
if [[ "${lateral_boundary_grid_file}" == "aa" ]]; then

    echo "Produce grid file for lateral boundary with iconsub."

    # load icontools
    spack load icontools

    # write icontools namelist
cat << EOF > iconsub_lateral_boundary.nl
&iconsub_nml
  grid_filename    = "/project/s1144/onadja/mch_ic_bc/grids/250m/domain2_DOM02.nc"
  output_type      = 4,
  lwrite_grid      = .TRUE.,
/
&subarea_nml
  ORDER            = "lateral_boundary",
  grf_info_file    = "/project/s1144/onadja/mch_ic_bc/grids/250m/domain2_DOM02.nc"
  min_refin_c_ctrl = 1
  max_refin_c_ctrl = 14
/

EOF

    # run icontools namelist
    iconsub --nml iconsub_lateral_boundary.nl

    # assign produced grid file
    lateral_boundary_grid_file="${wd}/lateral_boundary.grid.nc"

else
    echo "Use ${lateral_boundary_grid_file} for lateral boundary."

fi

# content for bc regridding
cat << EOF >> fx_prepare_bc.nl
!----------------------------------------------------------------------------------
! COSMO data is decoded with the help of dictionary_cosmo, and encoded as ICON data
! using dictionary_icon. Therefore, both dictionaries have to be specified.
!----------------------------------------------------------------------------------
&GlobalResource
 dictionary            = "/project/s83c/fieldextra/daint/resources/dictionary_icon.txt",
                         "/project/s83c/fieldextra/daint/resources/dictionary_cosmo.txt"
 grib_definition_path  = "/project/s83c/fieldextra/daint/resources/eccodes_definitions_cosmo",
                         "/project/s83c/fieldextra/daint/resources/eccodes_definitions_vendor"
 grib2_sample          = "/project/s83c/fieldextra/daint/resources/eccodes_samples/COSMO_GRIB2_default.tmpl"
 icon_grid_description = "/project/s1144/onadja/mch_ic_bc/grids/250m/domain2_DOM02.nc",
                         "${wd}/lateral_boundary.grid.nc"
/

!----------------------------------------------------------------------------------
! ICON is set as the default_model_name here, but since in_model_name and
! out_model_name are explicitely set in the I/O blocks, the default_model_name is
! actually not used in this example.
!----------------------------------------------------------------------------------
&GlobalSettings
  default_model_name            = "icon"
  !default_out_type_stdlongitude = .true.
/

&ModelSpecification
 model_name         = "cosmo"
 earth_axis_large   = 6371229.
 earth_axis_small   = 6371229.
/

! Radial basis function interpolation will be used as regrid_method to the ICON triangular
! grid for all fields.
!
&ModelSpecification
  model_name                = "icon"
  earth_axis_large          = 6371229.
  earth_axis_small          = 6371229.
  regrid_method             = "__ALL__:icontools,rbf"
/

!----------------------------------------------------------------------------------
! Use INCORE storage to tag the COSMO mass point grid for the re-gridding of U and V
!----------------------------------------------------------------------------------
&Process
  in_file = "/store/s83/osm/KENDA-1/ANA${yy}/det/laf20${date}"
  in_model_name="cosmo"
  out_type = "INCORE"
/
&Process in_field = "HSURF", tag="GRID_cosmo" /

!----------------------------------------------------------------------------------
! Read all necessary COSMO input fields.
! Rotate U and V, such that they refer to the geographical reference system.
! Scalar fields are re-gridded on output to the cell subgrid of the ICON triangular grid, which is
! specified in ../../resources/grid_descriptions/ICON-1E_DOM01_R19B08.nc.
! Radial basis function interpolation for vector fields is used to compute the edge normal wind
! component VN at the edge midpoints of the ICON grid from the horizontal wind compnents U and V.
! Note that out_model_name is set in the programme before the re-gridding takes place. Thus the default
! regrid_method that is defined in the ModelSpecification of ICON is used (and must be defined there).
!----------------------------------------------------------------------------------
! TODO: make dd adjustable, at the moment it only works for one day ... 
&Process
  in_file = "/store/s83/osm/KENDA-1/ANA${yy}/det/laf20${yy}${mm}${dd}<hh>"
  tstart=${hh}, tstop=${hl}, tincr=1
  in_model_name="cosmo"
  in_regrid_target="GRID_cosmo"
  in_regrid_method="average,square,0.9" ! only needed for U,V regridding with n2geog
  out_regrid_target = "icon_grid,cell,${wd}/lateral_boundary.grid.nc"
  out_regrid_method = "default"
  out_file = '${wd}/laf20${yy}${mm}${dd}<hh>_lbc.nc'
  out_model_name = "icon"
  out_type = "NETCDF", out_type_ncaspect="icon", out_type_nousetag=.true.
/

&Process in_field = "HEIGHT", level_class="k_half", levmin=1, levmax=81 /
&Process in_field = "U",  levmin=1, levmax=80, regrid=.t., poper="n2geog" /
&Process in_field = "V",  levmin=1, levmax=80, regrid=.t., poper="n2geog" /
&Process in_field = "W",  levmin=1, levmax=81 /
&Process in_field = "T",  levmin=1, levmax=80 /
&Process in_field = "P",  levmin=1, levmax=80 /
&Process in_field = "QV", levmin=1, levmax=80 /
&Process in_field = "QC", levmin=1, levmax=80 /
&Process in_field = "QI", levmin=1, levmax=80 /
&Process in_field = "QR", levmin=1, levmax=80 /
&Process in_field = "QS", levmin=1, levmax=80 /
&Process in_field = "QG", levmin=1, levmax=80 /
! &Process in_field = "PS" /
! &Process in_field = "FIS" /


&Process out_field = "HEIGHT", level_class="k_half", levmin=1, levmax=81 /
&Process out_field = "U",  levmin=1, levmax=80 /
&Process out_field = "V",  levmin=1, levmax=80 /
&Process out_field = "W",  levmin=1, levmax=81 /
&Process out_field = "T",  levmin=1, levmax=80 /
&Process out_field = "P",  levmin=1, levmax=80 /
&Process out_field = "QV", levmin=1, levmax=80 /
&Process out_field = "QC", levmin=1, levmax=80 /
&Process out_field = "QI", levmin=1, levmax=80 /
&Process out_field = "QR", levmin=1, levmax=80 /
&Process out_field = "QS", levmin=1, levmax=80 /
&Process out_field = "QG", levmin=1, levmax=80 /
! &Process out_field = "PS" / ! see figure 6.3 in the tutorial: if provided HHL -> read HHL, P, T, W
! &Process out_field = "FIS" / ! ignoring PS,GEOP,T. This way W is W and not OMEGA

EOF

# run fieldextra
$fieldextra fx_prepare_ic.nl
# $fieldextra fx_prepare_bc.nl

echo "Fieldextra namelist for regridding IC:" ${wd}/fx_prepare_ic.nl
echo "Fieldextra namelist for regridding BC:" ${wd}/fx_prepare_bc.nl
echo "LBC- and INI-files in:" ${wd}

