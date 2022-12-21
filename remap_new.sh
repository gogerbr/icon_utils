#!/bin/bash
set -e

#------------------------------------------------------------------------------
# Nadja Omanovic - 2022-07
# Remapping ICON to regular lat/lon grid with CDO. To speed up process only 
# a small number of variables is chosen to be remapped.
# Grid extent covers entire Switzerland. 
#------------------------------------------------------------------------------

module load CDO

# Give experiment name with flag options
while getopts f: flag
do 
	case "${flag}" in f) exp=${OPTARG};;
	       esac
done
echo "Experiment: $exp";

# Declare variables and directories
#model_dir="$SCRATCH/processing_chain/icon_inn/2019091300_0_1/icon/output/"
#model_dir="/scratch/snx3000/gogerb/processing_chain/icon-summer-500m/2022071800_0_24/icon/"
model_dir="/scratch/snx3000/gogerb/processing_chain/icon_inn/2019091300_0_1/icon/output2/d04/"

exp_dir="$model_dir$exp"
var_sel="u,v,w,z_ifc,topography_c,temp,pres"
#var_sel="z_ifc"
# make directory for remapped data
exp_remap="$exp"_remap4
mkdir -p $model_dir$exp_remap
dir_remap="$model_dir$exp_remap"

# get the grid specs for remapping the data

remap_specs="./remap_grid_specs_125m.txt"


# loop through all the files
for file in "$exp_dir"/"$exp"ICON_DOM04_00*

do 
## extract file name: we keep the file name for remapped files as well
    file_name=""${file##*/}
echo $file_name
				        
# create temporary file to do the actions on
tmp_file="$exp_dir"/tmp_"$file_name"
cdo -O select,name=$var_sel $file $tmp_file 
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
# (will be obsolete once we create our own model files)
# reduced the number of variables as it can get very time-consuming 
# if we have a lot of data points with variables in 3D
# the files have now the prefix "rmp" for being remapped, the rest stays the same 
# --> much easier to do flexible plotting scripts then
cdo -O remap,$remap_specs,"$dir_remap"/weights.nc $tmp_file "$dir_remap"/rmp_"$file_name"

# convert model levels to pressure levels
#-->SF's genius
#-- Figure out the list of levels from the fldavg of the file
format="%-5.0f"
coord_list=`cdo -s infov  -fldmean -selvar,"pres" $file | \
awk -v format="$format" '{printf format"\n",$9}' | \
    tr '\n' ',' | \
   sed -e 's/ *//g;s/,$//'`
#<--SF's genius
# here we us ap2pl instead of ml2pl, as ICON is nonhydrostatic, thus geomatric height is used for vertical coord.
# ap2pl is specifically designed for ICON model data
#cdo -O ap2pl,${coord_list} "$dir_remap"/rmp_"$file_name" "$dir_remap"/rmp_pl_"$file_name"
# now do a zonal mean on pressure levels, we keep both data sets
#cdo -O zonmean "$dir_remap"/rmp_"$file_name" "$dir_remap"/rmp_zon_"$file_name"
#cdo -O zonmean "$dir_remap"/rmp_pl_"$file_name" "$dir_remap"/rmp_pl_zon_"$file_name"
echo "$file_name: on Swiss grid and remapped and on pressure levels and zonal mean"
done
    # we remove the temporary files as we do not need them anymore
rm "$exp_dir"/tmp*
echo "All done!"


