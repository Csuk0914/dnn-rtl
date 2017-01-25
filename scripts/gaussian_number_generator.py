import numpy as np
import os

def gaussian_list_generate(fi, fo, int_bits, frac_bits, filename=os.path.dirname(os.path.realpath(__file__)) + '/s136_frc21_int10.dat'):
    ''' Remember to move the created file to dnn-rtl/gaussian_list'''
    filename_dec = filename[:-4]+'_DEC.dat' #write decimal values to file as well, for hlsims use    
    f = open(filename,'wb')
    f_dec = open(filename_dec,'wb')
    width = frac_bits + int_bits + 1 #1 for sign bit
    x = np.random.normal(0,np.sqrt(2./(fi+fo)),2000)
    x[x>2**int_bits-2**(-frac_bits)] = 2**int_bits-2**(-frac_bits) #positive limit
    x[x<-2**int_bits] = -2**int_bits #negative limit
    for i in xrange(len(x)):
        x_bin = format(int(2**(width+1) + x[i]*(2**frac_bits)), 'b')
        f.write('{0}\n'.format(x_bin[-width:]))
        f_dec.write('{0}\n'.format(x[i]))
    f.close()
    f_dec.close()

gaussian_list_generate(128,8,10,21, filename=os.path.dirname(os.path.realpath(__file__)) + '/s136_frc21_int10.dat')
gaussian_list_generate(32,8,10,21, filename=os.path.dirname(os.path.realpath(__file__)) + '/s40_frc21_int10.dat')