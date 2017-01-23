import random
import math

def gaussian_list_generate(fi, fo, frac_bit, int_bit):
    for i in range(2000):
        width = frac_bit + int_bit + 1
        x = random.gauss(0, math.sqrt(2/(fi+fo)))
        if x>16:
            x = 16
        elif x<-16:
            x = -16
        #print (x)
        x_bin = format(int(2**(width+1) + x * (2**frac_bit)), 'b')
        print (x_bin[-width:])

gaussian_list_generate(128,8,21,10)