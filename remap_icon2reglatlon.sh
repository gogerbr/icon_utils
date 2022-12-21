#!/bin/bash
set -e

#------------------------------------------------------------------------------
# Nadja Omanovic - 2022-07
# Remapping ICON to regular lat/lon grid with CDO. To speed up process only 
# a small number of variables is chosen to be remapped.
# Grid extent covers entire Switzerland. 
#------------------------------------------------------------------------------

#module load CDO
#module load cdo/1.9.7.1-fosscuda-2019b 
# Give experiment name with flag options
while getopts f: flag
do
    case "${flag}" in
        f) exp=${OPTARG};;
    esac
done
echo "Experiment: $exp";

# Declare variables and directories
#model_dir="/scratch/gogerb/icon/icon-summer-500m/20220718/"
model_dir="/scratch/snx3000/gogerb/processing_chain/icon-summer-500m/2022071800_0_24/icon/output/"
#model_dir="/users/gogerb/"
exp_dir="$model_dir"
#var_sel="u,v,w,tke,topography_c,temp,pres"
var_sel="topography_c","press,","u","v","w","temp",
# make directory for remapped data
exp_remap="$exp"_remap
mkdir -p $model_dir$exp_remap
dir_remap="$model_dir$exp_remap"

# get the grid specs for remapping the data
remap_specs="/users/gogerb/scripts/remap_grid_specs_ch.txt"

# Define grid box the data needs to be remapped to
box="sellonlatbox,3,12,45,49"

# loop through all the files
for file in "$exp_dir"/"$exp"

	
do 
    # extract file name: we keep the file name for remapped files as well
    file_name=""${file##*/}
    echo $file_name
    
    # create temporary file to do the actions on
    tmp_file="$exp_dir"/tmp_"$file_name"
    cdo -O select,name=$var_sel $file $tmp_file 
    cdo -O ${box} $tmp_file "$exp_dir"/tmp_box.nc
    echo $dir_remap
    # for remapping we need the weights file, check ICON documentation
    # here we do a first-order approximation
    # the other remap options, such as bil or similar do not work for ICON as it is unstructured
    if [ -e "$dir_remap"/weights.nc ]
    then
        echo "weights file exists"
    else
        cdo gencon,$remap_specs $tmp_file "$dir_remap"/weights.nc
        echo "weights file is created"
    fi

    # here the remapping is happening, we reduced the size of the grid 
    # (will be obsolete once we create our owen model files)
    # reduced the number of variables as it can get very time-consuming 
    # if we have a lot of data points with variables in 3D
    # the files have now the prefix "rmp" for being remapped, the rest stays the same 
    # --> much easier to do flexible plotting scripts then
    cdo -O remap,$remap_specs,"$dir_remap"/weights.nc $tmp_file "$dir_remap"/rmp_"$file_name"

    # convert model levels to pressure levels
    # here we us ap2pl instead of ml2pl, as ICON is nonhydrostatic, thus geomatric height is used for vertical coord.
    # ap2pl is specifically designed for ICON model data
 #   cdo -O ap2pl,2000/103500/1000 "$dir_remap"/rmp_"$file_name" "$dir_remap"/rmp_pl_"$file_name"

    # now do a zonal mean on pressure levels, we keep both data sets
#    cdo -O zonmean "$dir_remap"/rmp_pl_"$file_name" "$dir_remap"/rmp_pl_zon_"$file_name"
    echo "$file_name: on Swiss grid and remapped and on pressure levels and zonal mean"
done

# we remove the temporary files as we do not need them anymore
rm "$exp_dir"/tmp*
#rm "$exp_dir"/test.nc

echo "All done!"


