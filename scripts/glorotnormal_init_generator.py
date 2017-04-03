import numpy as np
import os

def glorotnormal_init_generate(fi, fo, int_bits, frac_bits, filename='s136_frc21_int10'):
    filename_bin = os.path.dirname(os.path.dirname(os.path.realpath(__file__))) + '/gaussian_list/'+filename+'.dat' #binary file for RTL use
    filename_dec = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath(__file__)))) + '/dnn-hlsims/network_models/wtbias_initdata/'+filename+'_DEC.dat' #write decimal values to file as well, for hlsims use    
    f_bin = open(filename_bin,'wb')
    f_dec = open(filename_dec,'wb')
    width = frac_bits + int_bits + 1 #1 for sign bit
    x = np.random.normal(0,np.sqrt(2./(fi+fo)), 2000)
    x[x>2**int_bits-2**(-frac_bits)] = 2**int_bits-2**(-frac_bits) #positive limit
    x[x<-2**int_bits] = -2**int_bits #negative limit
    for i in xrange(len(x)):
        x_bin = format(int(2**(width+1) + x[i]*(2**frac_bits)), 'b')
        f_bin.write('{0}\n'.format(x_bin[-width:]))
        f_dec.write('{0}\n'.format(x[i]))
    f_bin.close()
    f_dec.close()

########################## ONLY CHANGE THIS SECTION ###########################
#fi = [128,32]
#fo = [8,8]
fi = [8,8]
fo = [2,2]
int_bits = 2
frac_bits = 7
###############################################################################

glorotnormal_init_generate(fi[0],fo[0],int_bits,frac_bits, filename='/s{0}_frc{1}_int{2}'.format(fi[0]+fo[0],frac_bits,int_bits))
glorotnormal_init_generate(fi[1],fo[1],int_bits,frac_bits, filename='/s{0}_frc{1}_int{2}'.format(fi[1]+fo[1],frac_bits,int_bits))
