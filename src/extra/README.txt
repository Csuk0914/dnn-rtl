Extra code. To run, PUT FILES IN RESPECTIVE FOLDERS, like tb_mnist in testbench folder and rest in src folder.

eta_backtoparam:
	Converts eta to parameter (like it was previously), but value = -log(eta). Eg: If actual eta=0.0625, then eta = 4
	This enables easy use of shift operator or generate blocks based on eta value
	Introduces eta_en which is passed to junctions as input. Ensures that early updates don't happen
	NOT WORKING
	
eta_shift_impl
	Finds location of leading 1 in eta and converts that to shift information eta1pos. Eg: If eta=0.0625, eta1pos = 4
	Gives eta1pos as an input
	Uses always block and switch case to implement shift
	NOt WORKING