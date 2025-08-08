#!/bin/bash

rm -f result_savings.txt

export firstStepEP=3
export secStepEP=10
export thirdStepEP=1
export fourthStepEP=1
export PREC=1
export randOpt=1
export PFourth=80  

PFirst_VALUES=(40 50 60) 
PSec_VALUES=(40 50 60)    
PThird_VALUES=(80 90 100)

# Loop su CONFIG_ID e sui tre parametri
for CONFIG_ID in {0..13}; do
    for PFirst in "${PFirst_VALUES[@]}"; do
        for PSec in "${PSec_VALUES[@]}"; do
            for PThird in "${PThird_VALUES[@]}"; do
                
                export CONFIG_ID PFirst PSec PThird
                echo "Eseguo CONFIG_ID=$CONFIG_ID con PFirst=$PFirst PSec=$PSec PThird=$PThird"
                
                # Lancia PrimeTime e salva il log
                pt_shell -f ./scripts/noprint.tcl > "log_${CONFIG_ID}_${PFirst}_${PSec}_${PThird}.txt" 2>&1
            done
        done
    done
done
