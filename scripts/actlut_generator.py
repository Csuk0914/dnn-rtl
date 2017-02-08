# Generate look up tables for activation and activation derivative
# Output files from here used in sigmoid_sigmoidprime_table.v in dnn-rtl/src
# 'size' and 'maxdomain' here should match with 'lut_size' and 'maxdomain' in the RTL
# wordbits for sigmoid is USUALLY equal to frac_bits in the RTL, but may be less
# Output files from here may be deleted after copy-pasting to dnn-rtl/src

import numpy as np

def sigmoid(z):
    """The sigmoid function."""
    return 1.0/(1.0+np.exp(-z))

def sigmoid_prime(z):
    """Derivative of the sigmoid function."""
    return sigmoid(z)*(1-sigmoid(z))


def sigmoid_table_gen(size=256, wordbits=6, maxdomain=2):
    '''
    size: Total no. of cells in LUT
    wordbits: No. of bits in each cell
    maxdomain: sigmoid is only calculated for values within [-maxdomain,maxdomain)
    Each cell in the LUT = sigmoid(z), where z is the middle chunk of a number z in binary
    addr_xx_bits define how many integer and fractional part bits are taken for the LUT address
    E.g.:
        If maxdomain = 8, we need 4 sint bits (1 for sign + 3 integer) in the address
        Now if size = 4096, we need 12-bit addresses. So we must have 12-4 = 8 fractional bits in the adddress
    '''
    addr_sint_bits = 1 + int(np.log2(maxdomain)) #no. of sign + integer bits
    addr_frac_bits = int(np.log2(size)) - addr_sint_bits
    table = open("sigmoid_table.v", "wb")   
    for n in xrange(-size/2,size/2):
        z = float(n) / 2**addr_frac_bits #this ensures that z goes from -maxdomain to maxdomain
        s = sigmoid(z)
        addr = np.binary_repr(n,int(np.log2(size))) #table address
        value = np.binary_repr(int(round(s*2**wordbits)),wordbits)
        if len(value)>wordbits: #if overflow occurs, reduce to max value possible of wordbits size
            value = '1'
            for i in xrange(wordbits-1): value+='1'
        print  >> table, "\t\t{0}'b{1}:\tsigmoid = {2}'b{3};".format(int(np.log2(size)),addr,wordbits,value)
    table.close()
    
    
def sigmoidprime_table_gen(size=256, wordbits=4, maxdomain=2):
    '''
    KEY DIFFERENCE: sigmoidprime is always <0.25, so 1st 2 frac bits are always 0. So wordbits = actual frac bits - 2
    size: Total no. of cells in LUT
    wordbits: No. of bits in each cell (2 less than actual frac_bits)
    maxdomain: sigmoid prime is only calculated for values within [-maxdomain,maxdomain)
    Each cell in the LUT = 4*sigmoid'(z), where z is the middle chunk of a number z in binary
    addr_xx_bits define how many integer and fractional part bits are taken for the LUT address
    E.g.:
        If maxdomain = 8, we need 4 sint bits (1 for sign + 3 integer) in the address
        Now if size = 4096, we need 12-bit addresses. So we must have 12-4 = 8 fractional bits in the adddress
    '''
    addr_sint_bits = 1 + int(np.log2(maxdomain)) #no. of sign + integer bits
    addr_frac_bits = int(np.log2(size)) - addr_sint_bits
    table = open("sigmoidprime_table.v", "wb")   
    for n in xrange(-size/2,size/2):
        z = float(n) / 2**addr_frac_bits #this ensures that z goes from -maxdomain to maxdomain
        s = 4*sigmoid_prime(z) #multiply by 4 to stretch range to [0,1]
        addr = np.binary_repr(n,int(np.log2(size))) #table address
        value = np.binary_repr(int(round(s*2**wordbits)),wordbits)
        if len(value)>wordbits: #if overflow occurs, reduce to max value possible of wordbits size
            value = '1'
            for i in xrange(wordbits-1): value+='1'
        print  >> table, "\t\t{0}'b{1}:\tsigmoid_prime = {2}'b{3};".format(int(np.log2(size)),addr,wordbits,value)
    table.close()


sigmoid_table_gen()
sigmoidprime_table_gen()
