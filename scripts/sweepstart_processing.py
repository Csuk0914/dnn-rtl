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

f = open('sweepstart_4096_binlines.dat','rb')
f2 = open('sweepstart_4096_samelinehex','wb')
for line in f:
    f2.write(bin2hex(line[:4])+bin2hex(line[4:8]))
f.close()
f2.close()