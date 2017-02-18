import math

########### SET ################
# Speech
neurons = [128,4096,4096,4096,4096,4096,8192]
fo = [512,512,512,512,512,1024]
# ImageNet
neurons = [65536,8192,1024]
fo = [1024,128]
# Small trial
#neurons = [1024,32,16]
#fo = [2,2]
z_j01 = 64 #z of 1st junction
width = 16 #Bit width
###############################

##### GETS SET (DON'T SET) ####
W = [neurons[i]*fo[i] for i in xrange(len(fo))]
fi = [W[i]/neurons[i+1] for i in xrange(len(W))]
cpc = W[0]/z_j01
z = [[z_j01],[W[i]/cpc for i in xrange(1,len(W))]]
z = [item for sublist in z for item in sublist] #Make a flat list
###############################

######## I/O pins #############
##### SET #####
weights_readout = 8
biases_readout = 8
##################
io_pins = 0
io_pins += int(math.ceil(z[0]/float(fo[0]))) #act_in
io_pins += 3*int(math.ceil(z[-1]/float(fi[-1]))) #act_out, y_in, y_out
io_pins += 2 #clk, reset
io_pins += width*(weights_readout+biases_readout)
###############################

########### DSP ###############
ff_add = fi[:] #fi-1 tree adder + 1 bias adder = fi
ff_mult = z[:]

up_add = [z[i]+int(math.ceil(z[i]/float(fi[i]))) for i in xrange(len(z))]
up_mult = up_add[:]

bp_add = [z[i] for i in xrange(1,len(z))]
bp_mult = [2*z[i] for i in xrange(1,len(z))] #1 for w*d, 1 for that*act'

comp = z[:] #comparators used in state machine
cost_add = [int(math.ceil(z[-1]/float(fi[-1])))] #only for output layer

total_add = sum(comp)+sum(up_add)+sum(bp_add)+sum(ff_add)+sum(cost_add)
total_mult = sum(up_mult)+sum(bp_mult)+sum(ff_mult)
dsp_usage = total_mult*4
###############################

######### MEMORY ##############
wbmem_number = [z[i]+int(math.ceil(z[i]/float(fi[i]))) for i in xrange(len(z))] #total L-1
wbmem_cells = [cpc for i in xrange(len(z))]

actmem_coll = [2*(len(neurons)-i)-1 for i in xrange(len(z))]
actmem_number = z[:] #total L-1 (none for output layer)
actmem_cells = [neurons[i]/actmem_number[i] for i in xrange(len(actmem_number))]

actdermem_coll = actmem_coll[1:]
actdermem_number = actmem_number[1:] #total L-2 (none for input and hidden layers)
actdermem_cells = actmem_cells[1:]

delmem_coll = [2 for i in xrange(len(z))]
delmem_number = [actdermem_number[:],[int(math.ceil(z[-1]/float(fi[-1])))]] #total L-1 (none for input layer)
delmem_number = [item for sublist in delmem_number for item in sublist] #Make a flat list
delmem_cells = [neurons[i+1]/delmem_number[i] for i in xrange(len(delmem_number))]

total_wbmem = width*sum([wbmem_number[i]*wbmem_cells[i] for i in xrange(len(wbmem_number))])
total_actmem = (actmem_coll[0]*actmem_number[0]*actmem_cells[0] +
    width*sum([actmem_coll[i]*actmem_number[i]*actmem_cells[i] for i in xrange(1,len(actmem_number))])) #because input layer has width 1
total_actdermem = width*sum([actdermem_coll[i]*actdermem_number[i]*actdermem_cells[i] for i in xrange(len(actdermem_number))])
total_delmem = width*sum([delmem_coll[i]*delmem_number[i]*delmem_cells[i] for i in xrange(len(delmem_number))])

overhead_factor = 1.1 #due to other flipflops and registers
total_mem = (total_wbmem + total_actmem + total_actdermem + total_delmem) * overhead_factor
###############################

########### LUT ###############
##### SET #####
actlut_cells = 1024 #No. of cells in activation lookup table
actderlut_cells = 1024 #No. of cells in activation derivative lookup table
actlut_width = 8 #Bit width of each cell
actderlut_width = 8
###############

actlut_number = [int(math.ceil(z[i]/float(fi[i]))) for i in xrange(len(z))]
actderlut_number = actlut_number[:]

total_actlut = [actlut_number[i]*actlut_cells*actlut_width for i in xrange(len(actlut_number))]
total_actderlut = [actderlut_number[i]*actderlut_cells*actderlut_width for i in xrange(len(actderlut_number))]
underhead_factor = 0.5 #dunno why, vivado considers this
total_lut = (sum(total_actlut) + sum(total_actderlut)) * underhead_factor
###############################

########## REPORT #############
print
print '-------------------'
print 'Network Parameters'
print '-------------------'
print 'Neurons = {}'.format(neurons)
print 'Fanout = {}'.format(fo)
print 'Fanin = {}'.format(fi)
print 'No. of Weights = {}'.format(W)
print 'Degree of parallelism = {}'.format(z)
print 'Clocks per junction (minus 2) = {}'.format(cpc)
print 'Bit width = {}'.format(width)
print
print '-------------------'
print 'Usage Report:'
print '-------------------'
print 'IO pins = {0} ({1} weights and {2} biases read out)'.format(io_pins,weights_readout,biases_readout)
print 'DSP slices = {0} ({1} multipliers, {2} adders)'.format(dsp_usage,total_mult,total_add)
print 'Memory in Mbit (including AM, ADM, DM, WBM, flops) = {}'.format(float(total_mem)/1000000)
print 'LUTs in Mbit = {0} (each cell = {1} bits)'.format(float(total_lut)/1000000,actlut_width)
###############################