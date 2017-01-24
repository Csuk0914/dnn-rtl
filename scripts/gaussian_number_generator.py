import numpy as np
import os

def gaussian_list_generate(fi, fo, int_bits, frac_bits, filename='f'):
    width = frac_bits + int_bits + 1 #1 for sign bit
    x = np.random.normal(0,np.sqrt(2./(fi+fo)),2000)
    x[x>2**int_bits-2**(-frac_bits)] = 2**int_bits-2**(-frac_bits) #positive limit
    x[x<-2**int_bits] = -2**int_bits #negative limit
    for i in xrange(len(x)):
        x_bin = format(int(2**(width+1) + x[i]*(2**frac_bits)), 'b')
        print (x_bin[-width:])

gaussian_list_generate(128,8,10,21)