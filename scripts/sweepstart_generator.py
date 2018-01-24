### Generate sweepstart vector for each junction, i.e. the starting log(p/z) bit addresses for z memories in fo sweeps
### Copy-paste the outputs of sweepstart in interleaver_array.v
### Only change the 1st part

import numpy as np

#==============================================================================
# Only change this section: Set parameters here
#==============================================================================
n = np.array([1024,64,64])
fo = np.array([8,16])
z = np.array([128,16])
#==============================================================================
#==============================================================================



def bin2hex(b):
    ''' b should be 4-characters worth of 0s and 1s'''
    if type(b)!=str: b = str(b)
    if b=='0000': return '0'
    elif b=='0001': return '1'
    elif b=='0010': return '2'
    elif b=='0011': return '3'
    elif b=='0100': return '4'
    elif b=='0101': return '5'
    elif b=='0110': return '6'
    elif b=='0111': return '7'
    elif b=='1000': return '8'
    elif b=='1001': return '9'
    elif b=='1010': return 'a'
    elif b=='1011': return 'b'
    elif b=='1100': return 'c'
    elif b=='1101': return 'd'
    elif b=='1110': return 'e'
    elif b=='1111': return 'f'
    else: return 'Invalid'

def string_bin2hex(s):
    '''
    Convert a whole string from bin to hex, grouping the bits in sets of 4
    Adds 0s at end of necessary
    '''
    shex = ''
    x = len(s)%4
    if x!=0:
        for _ in xrange(4-x):
            s += '0'
    for i in xrange(0,len(s),4):
        shex += bin2hex(s[i:i+4])
    return shex

def create_sweepstart(p,fo,z):
    '''
    sweepstart has fo*z elements, each is a number between 0 and p/z-1
    Create this, then convert to binary and return as a string having fo*z*log2(p/z) characters
    '''
    ss = np.random.randint(0,p/z, fo*z)
    sweepstart = ''
    for s in ss:
        sweepstart += np.binary_repr(s, int(np.log2(p/z)))
    return sweepstart


print 'Size in bits of junction 1 sweepstart = {0}'.format(int(np.log2(n[0]/z[0])*fo[0]*z[0]))
print string_bin2hex(create_sweepstart(n[0],fo[0],z[0]))
print
print 'Size in bits of junction 2 sweepstart = {0}'.format(int(np.log2(n[1]/z[1])*fo[1]*z[1]))
print string_bin2hex(create_sweepstart(n[1],fo[1],z[1]))




#==============================================================================
#==============================================================================
# # OLD CODE
#==============================================================================
#==============================================================================

#Takes a multi-line file contains 8 binary digits per line (there may be tabs at the beginning of each line)
#Creates a single-line file which is the concatenation of all the binary digits (taken in sets of 4) in hex form

#Example input:
##01001111
##      00111010
##  11011100
##11110000

#Example output:
##4f3adcf0


#==============================================================================
# f = open('sweepstart_binlines.dat','rb') #input file
# f2 = open('sweepstart_samelinehex','wb') #output file
# for line in f:
#     line = line.replace('\t','')
#     f2.write(bin2hex(line[:4])+bin2hex(line[4:8]))
# f.close()
# f2.close()
#==============================================================================
