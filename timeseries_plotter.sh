

path1='/scratch/gogerb/icon/plot_profile/icon-summer-500m/'
path2='/scratch/gogerb/icon/plot_profile/icon-summer-500m-3d/'


date='22071800'
counter=0


#for loc in pay psi luz sio reh
plot_timeseries --loc loc --start 22071800 --end 22071823 --add_model icon 2m_temp 1 ref --add_model icon 2m_temp 1 exp --add_obs 2m temp --model_src ref /scratch/gogerb/icon/plot_profile/icon-summer-ifs/ 22071800 --model_src exp /scratch/gogerb/icon/plot_profile/icon-summer-1km-3d/ 22071800
#plot_timeseries --loc $loc --start $date --end 22071818 --add_model icon 2m_temp 1 ref --add_model icon 2m_temp 1 exp --add_obs 2m temp --model_src ref $path1 $date --model_src exp $path2 $date
#done


