#Takes a multi-line file contains 8 binary digits per line (there may be tabs at the beginning of each line)
#Creates a single-line file which is the concatenation of all the binary digits (taken in sets of 4) in hex form

#Example input:
##01001111
##      00111010
##  11011100
##11110000

#Example output:
##4f3adcf0

def bin2hex(b):
    ''' b should be a 4-character string of 0s and 1s'''
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

f = open('sweepstart_binlines.dat','rb') #input file
f2 = open('sweepstart_samelinehex','wb') #output file
for line in f:
    line = line.replace('\t','')
    f2.write(bin2hex(line[:4])+bin2hex(line[4:8]))
f.close()
f2.close()