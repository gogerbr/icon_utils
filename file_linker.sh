#!/bin/bash
echo linking output files! 

path1='/scratch/gogerb/icon/icon-summer-500m/20220718/'




date='20220718'
counter=0

while [ $counter -le 9 ]
do
        echo $counter
        ((counter++))

        file1='ICON_DOM01_000'$counter'0000.nc'

        file2='lfff000'$counter'0000.nc'
        ln -s $path1$file1 $file2
        echo linking $path1$file1 and $file2
done


counter=9
while [ $counter -le 23 ]
do
        echo $counter
        ((counter++))

        file1='ICON_DOM01_00'$counter'0000.nc'

        echo this is the filename  $file1        
        file2='lfff00'$counter'0000.nc'
        ln -s $path1$file1 $file2
        echo linking $path1$file1 and $file2
done




