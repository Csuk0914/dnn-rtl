# Create datasets for baby network configs for testing FPGA synthesis
# Each training sample has 0s and 1s and the output is the fraction of 1s (4 classes)
# Example: Consider a [64,16,4] network with 8-bit widths
    ## So each training input will have 64*8 = 512 combination of 0s and 1s
    ## If there are between 0 - 127 1s, output is 1000
    ## If there are between 128-256 1s, output is 0100. And so on
# Code isn;t completely parameterized.
    ## The output patterns like 0001 have to be manually changed if network config is changed

import numpy as np
import os
import random
from sweepstart_processing import bin2hex

NUM_TRAIN_INPUTS = 2000
NUM_INPUT_NEURONS = 64
NUM_OUTPUT_NEURONS = 4
WIDTH_IN = 8

fin = open(os.path.dirname(os.path.dirname(os.path.realpath('__file__')))+'/data/train_input_{0}'.format(NUM_INPUT_NEURONS)+'.dat','wb')
fout = open(os.path.dirname(os.path.dirname(os.path.realpath('__file__')))+'/data/train_idealout_{0}'.format(NUM_OUTPUT_NEURONS)+'.dat','wb')

inout_ratio = NUM_INPUT_NEURONS*WIDTH_IN/NUM_OUTPUT_NEURONS
for nti in xrange(NUM_TRAIN_INPUTS):
    count = np.random.randint(0,NUM_INPUT_NEURONS*WIDTH_IN+1) #number of 1s
    tempstr = ''
    for i in xrange(count): tempstr += '1'
    for j in xrange(count,NUM_INPUT_NEURONS*WIDTH_IN): tempstr += '0'
    tempstr = list(tempstr)
    random.shuffle(tempstr)
    s = ''.join(tempstr)
    for i in xrange(len(s)/4):
        fin.write(bin2hex(s[i*4:(i+1)*4]))
    fin.write('\n')
    if count<inout_ratio: fout.write('1000\n')
    elif inout_ratio<=count<2*inout_ratio: fout.write('0100\n')
    elif 2*inout_ratio<=count<3*inout_ratio: fout.write('0010\n')
    elif count>=3*inout_ratio: fout.write('0001\n')

fin.close()
fout.close()
# Actual program ends here

# Check distribution properties
fout = open(os.path.dirname(os.path.dirname(os.path.realpath('__file__')))+'/data/train_idealout_{0}'.format(NUM_OUTPUT_NEURONS)+'.dat','rb')
results = np.zeros(4)
for line in fout:
    if line == '1000\n': results[0]+=1
    elif line == '0100\n': results[1]+=1
    elif line == '0010\n': results[2]+=1
    elif line == '0001\n': results[3]+=1
print results
