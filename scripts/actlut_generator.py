# Generate look up tables for activation and activation derivative
# Output files from here used in sigmoid_sigmoidprime_table.v in dnn-rtl/src
# 'size' and 'maxdomain' here should match with 'lut_size' and 'maxdomain' in the RTL
# 'wordbits' is USUALLY equal to frac_bits in the RTL, but may be less

import numpy as np

def sigmoid(z):
    """The sigmoid function."""
    return 1.0/(1.0+np.exp(-z))

def sigmoid_prime(z):
    """Derivative of the sigmoid function."""
    return sigmoid(z)*(1-sigmoid(z))


def sigmoid_sigmoidprime_table_gen(size=4096, wordbits=12, maxdomain=8):
    '''
    sigmoid is between 0-1, but sigmoidprime is <0.25, so 1st 2 frac bits are always 0
    size: Total no. of cells in LUT
    wordbits: No. of bits in each cell
        For sigmoid: equal to frac_bits
        For sigmoid_prime: 2 less than frac_bits
    maxdomain: Only calculate for values within [-maxdomain,maxdomain)
    Each cell in the LUT:
        For sigmoid: sigmoid(z), where z is the middle chunk of a number z in binary
        For sigmoid_prime: 4*sigmoid'(z), where z is the middle chunk of a number z in binary
    addr_xx_bits define how many integer and fractional part bits are taken for the LUT address
    E.g.:
        If maxdomain = 8, we need 4 sint bits (1 for sign + 3 integer) in the address
        Now if size = 4096, we need 12-bit addresses. So we must have 12-4 = 8 fractional bits in the adddress
    '''
    addr_sint_bits = 1 + int(np.log2(maxdomain)) #no. of sign + integer bits
    addr_frac_bits = int(np.log2(size)) - addr_sint_bits
    table = open("sigmoid_sigmoidprime_table_size{0}_word{1}_maxdom{2}.dat".format(size,wordbits,maxdomain), "wb")

    for n in xrange(-size/2,size/2):
        z = float(n) / 2**addr_frac_bits #this ensures that z goes from -maxdomain to maxdomain
        s = sigmoid(z)
        sp = sigmoid_prime(z)

        addr = np.binary_repr(n,int(np.log2(size))) #table address
        value = np.binary_repr(int(round(s*2**wordbits)),wordbits)
        valuep = np.binary_repr(int(round(sp*2**wordbits)),wordbits-2)

        if len(value) > wordbits: #if overflow occurs, reduce to max value possible of wordbits size
            value = '1'
            for i in xrange(wordbits-1):
                value += '1'
        if len(valuep) > wordbits-2: #if overflow occurs, reduce to max value possible of wordbits size
            valuep = '1'
            for i in xrange(wordbits-3):
                valuep += '1'

        print  >> table, "\t\t{0}'b{1}: begin sigmoid <= {2}'b{3}; sigmoid_prime <= {4}'b{5}; end".format(int(np.log2(size)),addr,wordbits,value,wordbits-2,valuep)
    table.close()


########################## ONLY CHANGE THIS SECTION ###########################
size = 1024
wordbits = 6 #enter wordbits for sigmoid
maxdomain = 8
###############################################################################

sigmoid_sigmoidprime_table_gen(size=size, wordbits=wordbits, maxdomain=maxdomain)