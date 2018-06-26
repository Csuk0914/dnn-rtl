fr = open("train_input_ori.dat", "r")
fw = open("train_input.dat", "w")

for line in fr.readlines():
	for i in range(49):
		fw.write(line[i*32:i*32+32])
		fw.write('\n')

fr.close()
fw.close()