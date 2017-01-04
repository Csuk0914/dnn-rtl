import numpy as np

def table_gen():
    table1 = open("sigmoid_table.v", "w")
    table2 = open("sigmoid_prime_table.v", "w")
    print >> table1, "//sign, 3bits_i, 6bits_f ~ 0.015625  --->   8bits_f ~ 0.00390625"
    print >> table2, "//sign, 3bits_i, 6bits_f ~ 0.015625  --->   8bits_f ~ 0.0009766(3~10)"    
    for n in range(0, 1024):
        addr = (n-512.0 )/ 64.0
        s1 = sigmoid(addr)
        s2 = sigmoid_prime(addr)
        #print "sigmoid(",addr,"\t) = ",s
        print  >> table1, "\t\t10'b{:0>12b}:\tsigmoid = 8'b{:0>16b};" .format((n+512)%1024,int(s1*2**8))
        print  >> table2, "\t\t10'b{:0>12b}:\tsigmoid_prime = 8'b{:0>16b};" .format((n+512)%1024,int(s2*2**10))
    table1.close()
    table2.close()
    return


def sigmoid(z):
    """The sigmoid function."""
    return 1.0/(1.0+np.exp(-z))


def sigmoid_prime(z):
    """Derivative of the sigmoid function."""
    return sigmoid(z)*(1-sigmoid(z))

table_gen()
