#!/bin/bash

# Gather files to run an ICON-1 simulation for a specific date
# Author: Stephanie Westerhuis
# Date: July 15, 2022
 
# Usage:
# /path/to/prepare_case_study.sh YYMMDDHH
# /users/swester/runscripts/prepare_case_study.sh 22011800

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
echo "Prepare case study for 20${yy} ${mm} ${dd}, ${hh} UTC: +${leadtime}h"

# create working directory
# ------------------------
wd=${scr}/input_icon/$date
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
 verbosity             = "high"
 additional_diagnostic = .false.
 additional_profiling  = .true.
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
 dictionary            = "/project/s83c/fieldextra/tsa/resources/dictionary_icon.txt",
                         "/project/s83c/fieldextra/tsa/resources/dictionary_cosmo.txt"
 grib_definition_path  = "/project/s83c/fieldextra/tsa/resources/eccodes_definitions_cosmo",
                         "/project/s83c/fieldextra/tsa/resources/eccodes_definitions_vendor"
 grib2_sample          = "/project/s83c/fieldextra/tsa/resources/eccodes_samples/COSMO_GRIB2_default.tmpl"
 icon_grid_description = "/store/s83/tsm/ICON_INPUT/icon-1e_dev/ICON-1E_DOM01.nc"
/

!----------------------------------------------------------------------------------
! COSMO is set as the default_model_name here, but since in_model_name and
! out_model_name are explicitely set in the I/O blocks, the default_model_name is
! actually not used in this example.
!----------------------------------------------------------------------------------
&GlobalSettings
  default_model_name            = "cosmo-1e"
  default_out_type_stdlongitude = .true.
/

!----------------------------------------------------------------------------------
! The specification of the wilting_point and the field_capacity for the soil_types of
! the COSMO model is required for the computation of the soil moisture index.
!----------------------------------------------------------------------------------
&ModelSpecification
 model_name         = "cosmo-1e"
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
  in_file = "/store/s83/osm/KENDA-1/ANA${yy}/det/laf20${date}"
  in_model_name="cosmo-1e"
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
  in_file = "/store/s83/osm/KENDA-1/ANA${yy}/det/laf20${date}"
  in_model_name="cosmo-1e"
  in_regrid_target="GRID_cosmo", in_regrid_method="average,square,0.9"
  out_regrid_target = "icon_grid,cell,/store/s83/tsm/ICON_INPUT/icon-1e_dev/ICON-1E_DOM01.nc"
  out_regrid_method = "default"
  out_model_name = "icon"
  out_file = "${wd}/laf20${date}.nc",
  out_type = "NETCDF"
  out_mode_smi_clipped=.t.
  out_type_ncaspect="icon", out_type_ncnodegendim=.true.

/
&Process in_field = "W_SO" /
&Process in_field = "SOILTYP" /
&Process in_field="U", levmin=1, levmax=80, regrid=.t., poper="n2geog" /
&Process in_field="V", levmin=1, levmax=80, regrid=.t., poper="n2geog" /
&Process in_field="HHL", level_class="k_half", levmin=1, levmax=81 /
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
&Process in_field="W_SO_ICE" /
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

!----------------------------------------------------------------------------------
! Compute the SMI, and filter W_SO and SOILTYP.
!----------------------------------------------------------------------------------
&Process out_field="HHL", level_class="k_half", levmin=1, levmax=81 /
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
&Process out_field="SMI", poper="replace_undef,0." /
&Process out_field="W_SO_ICE" /
&Process out_field="FRESHSNW" /
&Process out_field="RHO_SNOW" /
&Process out_field="T_SNOW" /
&Process out_field="W_SNOW" /
&Process out_field="H_SNOW" /
&Process out_field="W_I" /
&Process out_field="Z0" /
&Process out_field="FR_ICE" /

EOF

# content for bc regridding
cat << EOF >> fx_prepare_bc.nl
!----------------------------------------------------------------------------------
! COSMO data is decoded with the help of dictionary_cosmo, and encoded as ICON data 
! using dictionary_icon. Therefore, both dictionaries have to be specified.
!----------------------------------------------------------------------------------
&GlobalResource
 dictionary            = "/project/s83c/fieldextra/tsa/resources/dictionary_icon.txt",
                         "/project/s83c/fieldextra/tsa/resources/dictionary_ifs.txt"
 grib_definition_path  = "/project/s83c/fieldextra/tsa/resources/eccodes_definitions_cosmo",
                         "/project/s83c/fieldextra/tsa/resources/eccodes_definitions_vendor"
 grib2_sample          = "/project/s83c/fieldextra/tsa/resources/eccodes_samples/COSMO_GRIB2_default.tmpl"
 icon_grid_description = "/store/s83/tsm/ICON_INPUT/icon-1e_dev/ICON-1E_DOM01.nc",
                         "/store/s83/tsm/ICON_INPUT/icon-1e_dev/lateral_boundary.grid.nc"
/


!----------------------------------------------------------------------------------
! ICON is set as the default_model_name here, but since in_model_name and
! out_model_name are explicitely set in the I/O blocks, the default_model_name is
! actually not used in this example.
!----------------------------------------------------------------------------------
&GlobalSettings
  default_model_name            = "ifs"
  default_out_type_stdlongitude = .true.
/

&ModelSpecification
 model_name         = "ifs"
 earth_axis_large   = 6371229.
 earth_axis_small   = 6371229.
 regrid_method      = "__ALL__:icontools,rbf"
/

!----------------------------------------------------------------------------------
! Read all necessary IFS input fields.
! Rotate U and V, such that they refer to the geographical reference system.
! Scalar fields are re-gridded on output to the cell subgrid of the ICON triangular grid
! Note that out_model_name is set in the programme before the re-gridding takes place. Thus the default
! regrid_method that is defined in the ModelSpecification of ICON is used (and must be defined there).
! A) for IFS analysis field
!----------------------------------------------------------------------------------
&Process
  in_file = "/store/s83/tsm/ICON_INPUT/ifs-hres/ifs-hres-bc_fi_ml1_137x091_01.grb2"
  out_type="INCORE"
/
&Process in_field = "FIS" /

&Process
  in_type="INCORE"
  out_regrid_target = "icon_grid,multiple,/store/s83/tsm/ICON_INPUT/icon-1e_dev/lateral_boundary.grid.nc"
  out_regrid_method = "default"
  out_file = "${wd}/efsf00000000_lbc.nc",
  out_type = "NETCDF", out_type_ncaspect = "icon", out_type_ncnodegendim=.TRUE.
/
&Process in_field = "FIS", set_reference_date=20${date} /

&Process
  in_file = "/store/s83/osm/IFS-HRES-BC/IFS-HRES-BC${yy}/${date}/eas20${date}"
  out_regrid_target = "icon_grid,multiple,/store/s83/tsm/ICON_INPUT/icon-1e_dev/lateral_boundary.grid.nc"
  out_regrid_method = "default"
  out_file = "${wd}/efsf00000000_lbc.nc",
  out_type = "NETCDF", out_type_ncaspect="icon", out_type_ncnodegendim=.true.
/

&Process in_field = "OMEGA", tag="W", levmin=1, levmax=137 /
&Process in_field = "T", levmin=1, levmax=137 /
&Process in_field = "QV", levmin=1, levmax=137 /
&Process in_field = "QC", levmin=1, levmax=137 /
&Process in_field = "QI", levmin=1, levmax=137 /
&Process in_field = "QR", levmin=1, levmax=137 /
&Process in_field = "QS", levmin=1, levmax=137 /
&Process in_field = "U", levmin=1, levmax=137, poper="n2geog" /
&Process in_field = "V", levmin=1, levmax=137, poper="n2geog" /
&Process in_field = "LNSP" /

&Process out_field = "OMEGA", tag="W", levmin=1, levmax=137 /
&Process out_field = "T", levmin=1, levmax=137 /
&Process out_field = "QV", levmin=1, levmax=137 /
&Process out_field = "QC", levmin=1, levmax=137 /
&Process out_field = "QI", levmin=1, levmax=137 /
&Process out_field = "QR", levmin=1, levmax=137 /
&Process out_field = "QS", levmin=1, levmax=137 /
&Process out_field = "U", levmin=1, levmax=137, regrid_operator="U,V>VN" /
&Process out_field = "V", levmin=1, levmax=137, regrid_operator="U,V>VN" /
&Process out_field = "LNSP", tag="LNPS" /
&Process out_field = "FIS", tag="GEOP_ML" /

EOF

# add block for remappig IFS forecast files only if specified leadtime > 0
if [[ $leadtime -gt 0 ]]; then

cat << EOF >> fx_prepare_bc.nl

! B) for IFS forecast fields
&Process
  in_type="INCORE"
  out_regrid_target = "icon_grid,multiple,/store/s83/tsm/ICON_INPUT/icon-1e_dev/lateral_boundary.grid.nc"
  out_regrid_method = "default"
  out_file = "${wd}/efsf<DDHH>0000_lbc.nc",
  out_type = "NETCDF", out_type_ncaspect = "icon", out_type_ncnodegendim=.TRUE.
  tstart=1, tstop=${leadtime}
/
&Process in_field = "FIS", set_reference_date=20${date} /

&Process
  in_file = "/store/s83/osm/IFS-HRES-BC/IFS-HRES-BC${yy}/${date}/efsf<DDHH>0000"
  out_regrid_target = "icon_grid,multiple,/store/s83/tsm/ICON_INPUT/icon-1e_dev/lateral_boundary.grid.nc"
  out_regrid_method = "default"
  out_file = "${wd}/efsf<DDHH>0000_lbc.nc",
  out_type = "NETCDF", out_type_ncaspect = "icon", out_type_ncnodegendim=.TRUE.
  tstart=1, tstop=${leadtime}
/

&Process in_field = "OMEGA", tag="W", levmin=1, levmax=137 /
&Process in_field = "T", levmin=1, levmax=137 /
&Process in_field = "QV", levmin=1, levmax=137 /
&Process in_field = "QC", levmin=1, levmax=137 /
&Process in_field = "QI", levmin=1, levmax=137 /
&Process in_field = "QR", levmin=1, levmax=137 /
&Process in_field = "QS", levmin=1, levmax=137 /
&Process in_field = "U", levmin=1, levmax=137, poper="n2geog" /
&Process in_field = "V", levmin=1, levmax=137, poper="n2geog" /
&Process in_field = "LNSP" /

&Process out_field = "OMEGA", tag="W", levmin=1, levmax=137 /
&Process out_field = "T", levmin=1, levmax=137 /
&Process out_field = "QV", levmin=1, levmax=137 /
&Process out_field = "QC", levmin=1, levmax=137 /
&Process out_field = "QI", levmin=1, levmax=137 /
&Process out_field = "QR", levmin=1, levmax=137 /
&Process out_field = "QS", levmin=1, levmax=137 /
&Process out_field = "U", levmin=1, levmax=137, regrid_operator="U,V>VN" /
&Process out_field = "V", levmin=1, levmax=137, regrid_operator="U,V>VN" /
&Process out_field = "LNSP", tag="LNPS" /
&Process out_field = "FIS", tag="GEOP_ML" /

EOF
fi # leadtime > 0

# run fieldextra
$fieldextra fx_prepare_ic.nl
$fieldextra fx_prepare_bc.nl

echo "Fieldextra namelist for regridding IC:" ${wd}/fx_prepare_ic.nl
echo "Fieldextra namelist for regridding BC:" ${wd}/fx_prepare_bc.nl
echo "LBC- and INI-files in:" ${wd}
