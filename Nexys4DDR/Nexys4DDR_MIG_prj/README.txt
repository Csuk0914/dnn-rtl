
These files will properly configure the MIG to work with the DDR2 on the Nexys4-DDR. 
These files are compatible with Vivado and ISE (Only tested in ISE 14.7). To use them,
insert a MIG IP Core into your design and launch the MIG Wizard. Then do the following:

1) In the MIG Ouput Options page, select "Verify Pin Changes and Update Design" and then
   click Next.

2) Select the mig.prj and mig.ucf files included with this download and click Next.

3) Click Validate, and then OK in the popup. You may ignore any warnings. Click Next.

4) Click Next, Until you reach the final page. At one point you will need to accept a 
   license agreement.

5) Click Generate.

6) The core should now be properly configured.

7) If you are using the XADC core elsewhere within your design, then you will need to 
reopen the wizard and disable the XADC Instantiation. You will then need to connect 
the device_temp signal to the XADC core in your design, as described in "Xilinx UG586
 7 Series FPGAs Memory Interface Solutions". 