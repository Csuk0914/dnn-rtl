#==============================================================================
# Given fi, fo, int_bits and frac_bits for some network config, generate Glorot Normal initialization files for weights and biases
# Default files are in binary and decimal
# Additional function convert2hex converts them to hexadecimal (0s are added as MSBs if needed)
# Sourya Dey, USC
#==============================================================================

import numpy as np
import os

def glorotnormal_init_generate(fi, fo, int_bits, frac_bits, numentries=2000, filename='s136_frc21_int10'):
    '''
    Outputs binary and decimal files of weight init values
    '''
    filename_bin = os.path.dirname(os.path.dirname(os.path.realpath('__file__'))) + '/gaussian_list/'+filename+'.dat' #binary file for RTL use
    filename_dec = os.path.dirname(os.path.dirname(os.path.dirname(os.path.realpath('__file__')))) + '/dnn-hlsims/network_models/wtbias_initdata/'+filename+'_DEC.dat' #write decimal values to file as well, for hlsims use
    f_bin = open(filename_bin,'wb')
    f_dec = open(filename_dec,'wb')
    width = frac_bits + int_bits + 1 #1 for sign bit
    x = np.random.normal(0,np.sqrt(2./(fi+fo)), numentries)
    x[x>2**int_bits-2**(-frac_bits)] = 2**int_bits-2**(-frac_bits) #positive limit
    x[x<-2**int_bits] = -2**int_bits #negative limit
    for i in xrange(len(x)):
        x_bin = format(int(2**(width+1) + x[i]*(2**frac_bits)), 'b')
        f_bin.write('{0}\n'.format(x_bin[-width:]))
        f_dec.write('{0}\n'.format(x[i]))
    f_bin.close()
    f_dec.close()

def convert2hex(filename_bin = os.path.dirname(os.path.dirname(os.path.realpath('__file__'))) + '/gaussian_list/s136_frc7_int2.dat'):
    '''
    Takes a file with binary numbers and converts to hex
    '''
    filename_hex = filename_bin[:-4] + '_HEX.dat'

    with open (filename_bin, 'rb') as f:
        flines = f.readlines()

    with open (filename_hex, 'wb') as f_hex:
        for i in xrange(len(flines)):
            line = flines[i].strip('\n')
            while len(line)%4 != 0:
                line = '0'+line #add 0s to get multiple of 4 bits
            f_hex_line = '' #Add new hex digits here
            for j in xrange(0, len(line), 4):
                f_hex_line += hex(int(line[j:j+4],2)).upper()[2:] #upper converts to capital, [2:] is to get rid of 0x at beginning
            f_hex.write('{0},'.format(f_hex_line)) #output has values separated by commas

def hex2mem(filename_hex = os.path.dirname(os.path.dirname(os.path.realpath('__file__')))+'/data/mnist/train_idealout_HEX.dat',
            depth=16):
    '''
    Takes a hex files as created by convert2hex() and converts it to mem form for giving init to Xilinx parametrized memory
    depth: Memory depth
    '''
    filename_mem = filename_hex[:-3] + 'mem'

    with open (filename_hex, 'rb') as f:
        flines = f.readlines()
    flines = flines[0].split(',')

    with open (filename_mem,'wb') as f_mem:
        for i in xrange(depth):
            f_mem.write('@{0} {1}\n'.format(hex(i).upper()[2:],flines[i]))




########################## ONLY CHANGE THIS SECTION ###########################
fo = [2,16]
fi = [32,32]
int_bits = 2
frac_bits = 7
###############################################################################

glorotnormal_init_generate(fi[0],fo[0],int_bits,frac_bits, filename='/s{0}_frc{1}_int{2}'.format(fi[0]+fo[0],frac_bits,int_bits))
glorotnormal_init_generate(fi[1],fo[1],int_bits,frac_bits, filename='/s{0}_frc{1}_int{2}'.format(fi[1]+fo[1],frac_bits,int_bits))
convert2hex(filename_bin = os.path.dirname(os.path.dirname(os.path.realpath('__file__')))+'/gaussian_list/s{0}_frc{1}_int{2}.dat'.format(fi[0]+fo[0],frac_bits,int_bits))
convert2hex(filename_bin = os.path.dirname(os.path.dirname(os.path.realpath('__file__')))+'/gaussian_list/s{0}_frc{1}_int{2}.dat'.format(fi[1]+fo[1],frac_bits,int_bits))

#convert2hex(filename_bin = os.path.dirname(os.path.dirname(os.path.realpath('__file__')))+'/data/mnist/train_idealout.dat')
#hex2mem(filename_hex = os.path.dirname(os.path.dirname(os.path.realpath('__file__'))) + '/data/mnist/train_idealout_HEX.dat',depth=12544)



