#Mahdi
#This file reads the output from the simulator
#and generates the histogram based on the values and accuracy
import matplotlib.pyplot as plt
import struct
import math
import sys

########################## ONLY CHANGE THIS SECTION ###########################
int_bits = 5
frac_bits = 10
base = 2
###############################################################################


# function for returning fractions
def calcul(val):
	totalfrac = 0
	intval = int(val[1:(int_bits+1)],base)
	for i in range(int_bits + 1, frac_bits + int_bits + 1):
		frac = int(val[i],base) * base**(-(i-int_bits))
		totalfrac += frac 
	if (int(val[0], 0) == 0): return(totalfrac + intval)
	else: 		       	  return(-1 * (totalfrac + intval))

# function for returning fractions
def calcul2(val):
	totalfrac = 0
	intval = int(val[1:(int_bits+2)],2)
	for i in range(int_bits + 2, frac_bits + int_bits + 1):
		frac = int(val[i],0) * base**(-(i-int_bits-1))
		totalfrac += frac 
	if (int(val[0], 0) == 0): return(totalfrac + intval)
	else: 		       	  return(-1 * (totalfrac + intval))	

# function for parsing the data
def data_parser(text, dic):
	for i, j in dic.iteritems():
	    text = text.replace(i,j)
	return text 

values = [1.2, 2.3, 1.2]
bins=[0.2, 1.1, 2.4, 3.5]
r = []
acc = []

reps = {'*':' ','+':' ',':':' ','=':' ',' ':' ','\n':''} 

realreps = open("realreps.dat","r")
inputfile = open("out.dat","r")
outputfile = open("out2.dat","w")

#read the values in fixed.point format and do the computation
#every line has arguments
for line in realreps:
		line2 = data_parser(line, reps)
		temp = line2.split(" ")
		print("Here is real rep values:")	
		print(float(temp[0]) + float(temp[2]))
		print(float(temp[0]) * float(temp[2]))

	#Exact values from computation: now in log domain
		print("Here is real rep values in log:")	
		num1 = math.log(float(temp[0]), base)
		num2 = math.log(float(temp[2]),base)	
		cf = math.log(1 + base ** (-abs(num1-num2)), base)
		print(math.pow(base, max(num1, num2) + cf ))
		print(math.pow(base, math.log(float(temp[0]),base) + math.log(float(temp[2]),base)) )

	#Approximation: values from computation in log domain 
		print("Approximated cf in log:")	
		num1 = math.log(float(temp[0]), base)
		num2 = math.log(float(temp[2]),base)
		print (num1, num2)		
		cf = base ** (-abs(num1-num2)) #in hardware approx. using a shifter	 
		print(math.pow(base, max(num1, num2) + cf ))
		print(math.pow(base, math.log(float(temp[0]),base) + math.log(float(temp[2]),base)) )

opType = input()
	
#read back the generated values from verilog computation
print("Here is values read back from FPGA:")

if(opType == "add"):
   	
	for line in inputfile:
	    line2 = data_parser(line, reps)
	    temp = line2.split(" ")
	    #unpack the string values to binary	
	    val1 = struct.unpack('16s', temp[0])[0]   #X
	    val2 = struct.unpack('16s', temp[8])[0]   #Y
	    res = struct.unpack('16s', temp[13])[0]

	    #compute exact and approx values	
	    exact = (base ** calcul(res))
	    approx = (base**calcul(val1) + base**calcul(val2))	
	    dev = abs(approx - exact)

	    print( calcul(val1) ,"+", calcul(val2), "=", calcul(res))
	    print( "Exact number:" , (base**calcul(val1) + base**calcul(val2)) )
	    print( "Hardware Approx. number:", base ** calcul(res))
	    print( "r is:", abs(calcul(val1) - calcul(val2)), "acc rate is:", abs(exact - dev)/exact )

	    r.insert (0, abs(calcul(val1) - calcul(val2))) # r = |X - Y|
	    acc.insert (0, abs(exact - dev) / exact) # acc% = approx./exact

elif (opType == "mult"):
   	
	for line in inputfile:
	    line2 = data_parser(line, reps)
	    temp = line2.split(" ")
	    #unpack the string values to binary	
	    val1 = struct.unpack('16s', temp[0])[0]   #X
	    val2 = struct.unpack('16s', temp[8])[0]   #Y
	    res = struct.unpack('17s', temp[13])[0]
	
	    #compute exact and approx values	
	    exact = (base ** calcul2(res))
	    approx = (base**calcul(val1) * base**calcul(val2))	
	    dev = abs(approx - exact)

	    print( calcul(val1) ,"*", calcul(val2), "=", calcul2(res), "which was", res)
	    print( "Exact number:" , (base**calcul(val1) * base**calcul(val2)) )
	    print( "Hardware Approx. number:", base ** calcul2(res))


	    r.insert (0, abs(calcul(val1) - calcul(val2))) # r = |X - Y|
	    acc.insert (0, abs(exact - dev) / exact) # acc% = approx./exact

else: 
	  print("Sorry, operator not supported.") 
	  sys.exit(0)		
	
plt.scatter(r,acc)

plt.xlabel('r = |X - Y|', fontsize=18)
plt.ylabel('accuracy %', fontsize=16)
plt.show()

#close files
inputfile.close()
outputfile.close()
